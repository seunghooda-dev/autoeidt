import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models/highlight_segment.dart';
import '../models/job_models.dart';
import '../utils/timecode.dart';
import 'time_format.dart';

enum _DragEdge { start, end }

enum _DragTrack { video, audio1, audio2 }

class _TimelinePlacement {
  const _TimelinePlacement({
    required this.segment,
    required this.index,
    required this.sequenceStart,
    required this.sequenceEnd,
    required this.transitionOverlap,
  });

  final HighlightSegment segment;
  final int index;
  final double sequenceStart;
  final double sequenceEnd;
  final double transitionOverlap;

  double get speed => math.max(0.1, segment.playbackSpeed);
  double get audioStart =>
      sequenceStart + (segment.effectiveAudioStart - segment.start) / speed;
  double get audioEnd =>
      sequenceStart + (segment.effectiveAudioEnd - segment.start) / speed;
}

List<_TimelinePlacement> _buildTimelinePlacements(
  List<HighlightSegment> segments,
) {
  var cursor = 0.0;
  HighlightSegment? previous;
  return [
    for (var index = 0; index < segments.length; index++)
      (() {
        final segment = segments[index];
        final overlap = previous == null
            ? 0.0
            : effectiveTransitionOverlap(previous!, segment);
        final start = math.max(0.0, cursor - overlap);
        final end = start + math.max(0.0, segment.outputDuration);
        cursor = end;
        previous = segment;
        return _TimelinePlacement(
          segment: segment,
          index: index,
          sequenceStart: start,
          sequenceEnd: end,
          transitionOverlap: overlap,
        );
      })(),
  ];
}

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
    this.videoOverlays = const [],
    this.audioClips = const [],
    required this.playheadSeconds,
    required this.selectedSegmentOrder,
    this.selectedVideoOverlayId,
    this.selectedAudioClipId,
    required this.markIn,
    required this.markOut,
    required this.timelineMarkers,
    required this.waveform,
    this.timelineThumbnails = const {},
    required this.zoom,
    required this.trackHeightScale,
    required this.snappingEnabled,
    required this.videoTrackTargeted,
    this.videoOverlayTrackTargeted = true,
    required this.audioTrack1Targeted,
    required this.audioTrack2Targeted,
    this.audioTrack3Targeted = true,
    this.activeVideoTrackCount = 2,
    this.activeAudioTrackCount = 3,
    this.targetedVideoOverlayTrack = 2,
    this.targetedOverlayAudioTrack = 3,
    required this.videoTrackLocked,
    this.videoOverlayTrackLocked = false,
    this.videoOverlayTrackVisible = true,
    this.lockedVideoOverlayTracks = const <int>{},
    this.hiddenVideoOverlayTracks = const <int>{},
    required this.audioTrackLocked,
    required this.audioTrack1Locked,
    required this.audioTrack2Locked,
    this.audioTrack3Locked = false,
    this.lockedAuxiliaryAudioTracks = const <int>{},
    this.mutedAuxiliaryAudioTracks = const <int>{},
    this.soloAudioTracks = const <int>{},
    required this.razorTool,
    required this.onSegmentChanged,
    this.onVideoOverlayChanged,
    this.onAudioClipChanged,
    required this.onScrub,
    required this.onSegmentSelected,
    this.onVideoOverlaySelected,
    this.onAudioClipSelected,
    this.sequenceMode = false,
    this.sourceDuration,
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
    this.onToggleAudio3Target,
    this.onToggleVideoLock,
    this.onToggleAudio1Lock,
    this.onToggleAudio2Lock,
    this.onToggleAudio3Lock,
    this.onToggleClipEnabled,
    this.onToggleVideoEnabled,
    this.onResetAudioPan,
    this.onToggleVideoOverlayTarget,
    this.onToggleVideoOverlayTargetAt,
    this.onToggleVideoOverlayLock,
    this.onToggleVideoOverlayLockAt,
    this.onToggleVideoOverlayVisibility,
    this.onToggleVideoOverlayVisibilityAt,
    this.onToggleVideoOverlayAudio,
    this.onToggleOverlayAudioTargetAt,
    this.onToggleOverlayAudioAt,
    this.onToggleAuxiliaryAudioLockAt,
    this.onToggleAudioSoloAt,
    this.onDeleteVideoOverlay,
    this.onDeleteAudioClip,
    this.onZoomDelta,
  });

  final double duration;
  final List<HighlightSegment> segments;
  final List<VideoOverlayClip> videoOverlays;
  final List<AudioClip> audioClips;
  final double playheadSeconds;
  final int? selectedSegmentOrder;
  final String? selectedVideoOverlayId;
  final String? selectedAudioClipId;
  final double? markIn;
  final double? markOut;
  final List<TimelineMarker> timelineMarkers;
  final List<double> waveform;
  final Map<int, ui.Image> timelineThumbnails;
  final double zoom;
  final double trackHeightScale;
  final bool snappingEnabled;
  final bool videoTrackTargeted;
  final bool videoOverlayTrackTargeted;
  final bool audioTrack1Targeted;
  final bool audioTrack2Targeted;
  final bool audioTrack3Targeted;
  final int activeVideoTrackCount;
  final int activeAudioTrackCount;
  final int targetedVideoOverlayTrack;
  final int targetedOverlayAudioTrack;
  final bool videoTrackLocked;
  final bool videoOverlayTrackLocked;
  final bool videoOverlayTrackVisible;
  final Set<int> lockedVideoOverlayTracks;
  final Set<int> hiddenVideoOverlayTracks;
  final bool audioTrackLocked;
  final bool audioTrack1Locked;
  final bool audioTrack2Locked;
  final bool audioTrack3Locked;
  final Set<int> lockedAuxiliaryAudioTracks;
  final Set<int> mutedAuxiliaryAudioTracks;
  final Set<int> soloAudioTracks;
  final bool razorTool;
  final ValueChanged<HighlightSegment> onSegmentChanged;
  final ValueChanged<VideoOverlayClip>? onVideoOverlayChanged;
  final ValueChanged<AudioClip>? onAudioClipChanged;
  final ValueChanged<double> onScrub;
  final ValueChanged<int> onSegmentSelected;
  final ValueChanged<String>? onVideoOverlaySelected;
  final ValueChanged<String>? onAudioClipSelected;
  final bool sequenceMode;
  final double? sourceDuration;
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
  final VoidCallback? onToggleAudio3Target;
  final VoidCallback? onToggleVideoLock;
  final VoidCallback? onToggleAudio1Lock;
  final VoidCallback? onToggleAudio2Lock;
  final VoidCallback? onToggleAudio3Lock;
  final VoidCallback? onToggleClipEnabled;
  final VoidCallback? onToggleVideoEnabled;
  final VoidCallback? onResetAudioPan;
  final VoidCallback? onToggleVideoOverlayTarget;
  final ValueChanged<int>? onToggleVideoOverlayTargetAt;
  final VoidCallback? onToggleVideoOverlayLock;
  final ValueChanged<int>? onToggleVideoOverlayLockAt;
  final VoidCallback? onToggleVideoOverlayVisibility;
  final ValueChanged<int>? onToggleVideoOverlayVisibilityAt;
  final VoidCallback? onToggleVideoOverlayAudio;
  final ValueChanged<int>? onToggleOverlayAudioTargetAt;
  final ValueChanged<int>? onToggleOverlayAudioAt;
  final ValueChanged<int>? onToggleAuxiliaryAudioLockAt;
  final ValueChanged<int>? onToggleAudioSoloAt;
  final VoidCallback? onDeleteVideoOverlay;
  final VoidCallback? onDeleteAudioClip;
  final ValueChanged<double>? onZoomDelta;

  @override
  State<TimelineEditor> createState() => _TimelineEditorState();
}

class _TimelineLayout {
  const _TimelineLayout({
    required double scale,
    required this.activeVideoTracks,
    required this.activeAudioTracks,
  }) : scale = scale < 0.75
           ? 0.75
           : scale > 1.35
           ? 1.35
           : scale;

  final double scale;
  final int activeVideoTracks;
  final int activeAudioTracks;
  double get rulerHeight => 30;
  double get overlayTop => rulerHeight + 2;
  double get laneHeight => 27 * scale;
  double get laneGap => 2;
  double videoTrackTop(int track) =>
      overlayTop + (activeVideoTracks - track) * (laneHeight + laneGap);
  double get videoTop => videoTrackTop(1);
  double get audioTracksTop => videoTop + laneHeight + laneGap;
  double audioTrackTop(int track) =>
      audioTracksTop + (track - 1) * (laneHeight + laneGap);
  double get audio1Top => audioTrackTop(1);
  double get audio2Top => audioTrackTop(2);
  double get audio3Top => audioTrackTop(3);
  double get footerTop => audioTrackTop(activeAudioTracks) + laneHeight + 4;
  double get canvasHeight => footerTop + 28;
  double get trackBottom => audioTrackTop(activeAudioTracks) + laneHeight;
}

class _TimelineEditorState extends State<TimelineEditor> {
  static const double _trackHeaderWidth = 172;
  static const double _snapHitWidth = 10;
  static const double _handleHitWidth = 16;
  static const double _handleVisualWidth = 2;
  static const double _minSegmentSeconds = 1.0;

  int? _activeIndex;
  _DragEdge? _activeEdge;
  _DragTrack? _activeTrack;
  bool _isScrubbing = false;
  final ScrollController _scrollController = ScrollController();
  final ScrollController _verticalScrollController = ScrollController();
  double _lastViewportWidth = 0;
  double? _pendingZoomFocalRatio;
  double? _pendingZoomViewportX;
  HighlightSegment? _dragOriginSegment;
  double? _dragOriginSequenceStart;
  int? _activePointer;
  Offset? _pointerDownPosition;
  bool _pointerDragging = false;
  bool _followPlayheadScheduled = false;
  _TimelineLayout get _layout => _TimelineLayout(
    scale: widget.trackHeightScale,
    activeVideoTracks: widget.activeVideoTrackCount.clamp(1, 4).toInt(),
    activeAudioTracks: widget.activeAudioTrackCount.clamp(2, 8).toInt(),
  );

  bool _videoOverlayLocked(int track) =>
      widget.lockedVideoOverlayTracks.contains(track) ||
      (widget.lockedVideoOverlayTracks.isEmpty &&
          widget.videoOverlayTrackLocked);

  bool _videoOverlayVisible(int track) =>
      !widget.hiddenVideoOverlayTracks.contains(track) &&
      (widget.hiddenVideoOverlayTracks.isNotEmpty ||
          widget.videoOverlayTrackVisible);

  bool _auxiliaryAudioLocked(int track) =>
      widget.lockedAuxiliaryAudioTracks.contains(track) ||
      (widget.lockedAuxiliaryAudioTracks.isEmpty && widget.audioTrack3Locked);

  bool _auxiliaryAudioMuted(int track) =>
      widget.mutedAuxiliaryAudioTracks.contains(track);

  bool _audioTrackIncludedBySolo(int track) =>
      widget.soloAudioTracks.isEmpty || widget.soloAudioTracks.contains(track);

  List<_TimelinePlacement> get _placements =>
      _buildTimelinePlacements(widget.segments);

  @override
  void didUpdateWidget(covariant TimelineEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sequenceMode != widget.sequenceMode ||
        oldWidget.playheadSeconds != widget.playheadSeconds) {
      _schedulePlayheadVisibility(
        center: oldWidget.sequenceMode != widget.sequenceMode,
      );
    }
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

  void _schedulePlayheadVisibility({required bool center}) {
    if (_followPlayheadScheduled) {
      return;
    }
    _followPlayheadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _followPlayheadScheduled = false;
      if (!mounted ||
          !_scrollController.hasClients ||
          _lastViewportWidth <= 0 ||
          widget.duration <= 0 ||
          _pointerDragging) {
        return;
      }
      final playheadX =
          (widget.playheadSeconds / widget.duration).clamp(0.0, 1.0) *
          _lastViewportWidth *
          widget.zoom;
      final current = _scrollController.offset;
      final margin = math.min(56.0, _lastViewportWidth * 0.12);
      final visible =
          playheadX >= current + margin &&
          playheadX <= current + _lastViewportWidth - margin;
      if (!center && visible) {
        return;
      }
      final target = playheadX - _lastViewportWidth / 2;
      _scrollController.jumpTo(
        target
            .clamp(0.0, _scrollController.position.maxScrollExtent)
            .toDouble(),
      );
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _verticalScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = _layout;
        final viewportWidth = math.max(
          120.0,
          constraints.maxWidth - _trackHeaderWidth - 1,
        );
        _lastViewportWidth = viewportWidth;
        final width = viewportWidth * widget.zoom;
        return Semantics(
          label: widget.sequenceMode
              ? 'Sequence timeline ${formatSeconds(widget.duration)}'
              : 'Source timeline ${formatSeconds(widget.duration)}',
          child: SizedBox(
            height: constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : layout.canvasHeight,
            child: Scrollbar(
              controller: _verticalScrollController,
              thumbVisibility:
                  constraints.maxHeight.isFinite &&
                  layout.canvasHeight > constraints.maxHeight,
              child: SingleChildScrollView(
                key: const Key('timeline-vertical-scroll'),
                controller: _verticalScrollController,
                child: SizedBox(
                  height: layout.canvasHeight,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: _trackHeaderWidth,
                        child: _TimelineTrackHeaders(
                          layout: layout,
                          segments: widget.segments,
                          videoOverlays: widget.videoOverlays,
                          audioClips: widget.audioClips,
                          activeVideoTrackCount: layout.activeVideoTracks,
                          activeAudioTrackCount: layout.activeAudioTracks,
                          targetedVideoOverlayTrack:
                              widget.targetedVideoOverlayTrack,
                          targetedOverlayAudioTrack:
                              widget.targetedOverlayAudioTrack,
                          overlayTargeted: widget.videoOverlayTrackTargeted,
                          videoTargeted: widget.videoTrackTargeted,
                          audio1Targeted: widget.audioTrack1Targeted,
                          audio2Targeted: widget.audioTrack2Targeted,
                          audio3Targeted: widget.audioTrack3Targeted,
                          videoLocked: widget.videoTrackLocked,
                          overlayLocked: widget.videoOverlayTrackLocked,
                          overlayVisible: widget.videoOverlayTrackVisible,
                          lockedVideoOverlayTracks:
                              widget.lockedVideoOverlayTracks,
                          hiddenVideoOverlayTracks:
                              widget.hiddenVideoOverlayTracks,
                          audio1Locked:
                              widget.audioTrackLocked ||
                              widget.audioTrack1Locked,
                          audio2Locked:
                              widget.audioTrackLocked ||
                              widget.audioTrack2Locked,
                          audio3Locked: widget.audioTrack3Locked,
                          lockedAuxiliaryAudioTracks:
                              widget.lockedAuxiliaryAudioTracks,
                          mutedAuxiliaryAudioTracks:
                              widget.mutedAuxiliaryAudioTracks,
                          soloAudioTracks: widget.soloAudioTracks,
                          onToggleVideoTarget: widget.onToggleVideoTarget,
                          onToggleOverlayTarget:
                              widget.onToggleVideoOverlayTarget,
                          onToggleOverlayTargetAt:
                              widget.onToggleVideoOverlayTargetAt,
                          onToggleAudio1Target: widget.onToggleAudio1Target,
                          onToggleAudio2Target: widget.onToggleAudio2Target,
                          onToggleAudio3Target: widget.onToggleAudio3Target,
                          onToggleVideoLock: widget.onToggleVideoLock,
                          onToggleOverlayLock: widget.onToggleVideoOverlayLock,
                          onToggleOverlayLockAt:
                              widget.onToggleVideoOverlayLockAt,
                          onToggleOverlayVisibility:
                              widget.onToggleVideoOverlayVisibility,
                          onToggleOverlayVisibilityAt:
                              widget.onToggleVideoOverlayVisibilityAt,
                          onToggleAudio1Lock: widget.onToggleAudio1Lock,
                          onToggleAudio2Lock: widget.onToggleAudio2Lock,
                          onToggleAudio3Lock: widget.onToggleAudio3Lock,
                          onToggleAuxiliaryAudioLockAt:
                              widget.onToggleAuxiliaryAudioLockAt,
                          onToggleAudioSoloAt: widget.onToggleAudioSoloAt,
                          onToggleAudio1: widget.onToggleAllAudioChannel1,
                          onToggleAudio2: widget.onToggleAllAudioChannel2,
                          onToggleAudio3: widget.onToggleVideoOverlayAudio,
                          onToggleOverlayAudioTargetAt:
                              widget.onToggleOverlayAudioTargetAt,
                          onToggleOverlayAudioAt: widget.onToggleOverlayAudioAt,
                        ),
                      ),
                      VerticalDivider(
                        width: 1,
                        thickness: 1,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      Expanded(
                        key: const Key('timeline-scroll-area'),
                        child: Listener(
                          onPointerSignal: _handlePointerSignal,
                          child: Scrollbar(
                            controller: _scrollController,
                            thumbVisibility: widget.zoom > 1.0,
                            child: SingleChildScrollView(
                              controller: _scrollController,
                              scrollDirection: Axis.horizontal,
                              physics: _pointerDragging
                                  ? const NeverScrollableScrollPhysics()
                                  : const ClampingScrollPhysics(),
                              child: Listener(
                                behavior: HitTestBehavior.opaque,
                                onPointerDown: (event) =>
                                    _handlePointerDown(event),
                                onPointerMove: (event) =>
                                    _handlePointerMove(event, width),
                                onPointerUp: _handlePointerEnd,
                                onPointerCancel: _handlePointerEnd,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTapDown: (details) =>
                                      _tap(details.localPosition, width),
                                  onSecondaryTapDown: (details) =>
                                      _showContextMenu(details, width),
                                  child: SizedBox(
                                    width: width,
                                    height: layout.canvasHeight,
                                    child: CustomPaint(
                                      key: const Key('timeline-canvas'),
                                      painter: _TimelinePainter(
                                        layout: layout,
                                        duration: widget.duration,
                                        segments: widget.segments,
                                        playheadSeconds: widget.playheadSeconds,
                                        selectedSegmentOrder:
                                            widget.selectedSegmentOrder,
                                        markIn: widget.markIn,
                                        markOut: widget.markOut,
                                        timelineMarkers: widget.timelineMarkers,
                                        waveform: widget.waveform,
                                        timelineThumbnails:
                                            widget.timelineThumbnails,
                                        activeIndex: _activeIndex,
                                        activeEdge: _activeEdge,
                                        activeTrack: _activeTrack,
                                        videoTrackLocked:
                                            widget.videoTrackLocked,
                                        audioTrack1Locked:
                                            widget.audioTrackLocked ||
                                            widget.audioTrack1Locked,
                                        audioTrack2Locked:
                                            widget.audioTrackLocked ||
                                            widget.audioTrack2Locked,
                                        colorScheme: Theme.of(
                                          context,
                                        ).colorScheme,
                                        sequenceMode: widget.sequenceMode,
                                        sourceDuration:
                                            widget.sourceDuration ??
                                            widget.duration,
                                      ),
                                      child: Stack(
                                        children: [
                                          if (widget.sequenceMode)
                                            for (final overlay
                                                in widget.videoOverlays)
                                              _VideoOverlayBlock(
                                                overlay: overlay,
                                                duration: widget.duration,
                                                canvasWidth: width,
                                                top:
                                                    layout.videoTrackTop(
                                                      overlay.videoTrack
                                                          .clamp(
                                                            2,
                                                            layout
                                                                .activeVideoTracks,
                                                          )
                                                          .toInt(),
                                                    ) +
                                                    2,
                                                height: layout.laneHeight - 4,
                                                selected:
                                                    widget
                                                        .selectedVideoOverlayId ==
                                                    overlay.id,
                                                locked: _videoOverlayLocked(
                                                  overlay.videoTrack,
                                                ),
                                                trackVisible:
                                                    _videoOverlayVisible(
                                                      overlay.videoTrack,
                                                    ),
                                                onSelected: widget
                                                    .onVideoOverlaySelected,
                                                onChanged: widget
                                                    .onVideoOverlayChanged,
                                                onDelete:
                                                    widget.onDeleteVideoOverlay,
                                              ),
                                          if (widget.sequenceMode)
                                            for (final overlay
                                                in widget.videoOverlays)
                                              _VideoOverlayAudioBlock(
                                                overlay: overlay,
                                                duration: widget.duration,
                                                canvasWidth: width,
                                                top:
                                                    layout.audioTrackTop(
                                                      overlay.audioTrack
                                                          .clamp(
                                                            3,
                                                            layout
                                                                .activeAudioTracks,
                                                          )
                                                          .toInt(),
                                                    ) +
                                                    2,
                                                height: layout.laneHeight - 4,
                                                selected:
                                                    widget
                                                        .selectedVideoOverlayId ==
                                                    overlay.id,
                                                locked: _auxiliaryAudioLocked(
                                                  overlay.audioTrack,
                                                ),
                                                trackMuted:
                                                    _auxiliaryAudioMuted(
                                                      overlay.audioTrack,
                                                    ) ||
                                                    !_audioTrackIncludedBySolo(
                                                      overlay.audioTrack,
                                                    ),
                                                onSelected: widget
                                                    .onVideoOverlaySelected,
                                              ),
                                          if (widget.sequenceMode)
                                            for (final clip
                                                in widget.audioClips)
                                              _StandaloneAudioBlock(
                                                clip: clip,
                                                duration: widget.duration,
                                                canvasWidth: width,
                                                top:
                                                    layout.audioTrackTop(
                                                      clip.track
                                                          .clamp(
                                                            3,
                                                            layout
                                                                .activeAudioTracks,
                                                          )
                                                          .toInt(),
                                                    ) +
                                                    2,
                                                height: layout.laneHeight - 4,
                                                selected:
                                                    widget
                                                        .selectedAudioClipId ==
                                                    clip.id,
                                                locked: _auxiliaryAudioLocked(
                                                  clip.track,
                                                ),
                                                trackMuted:
                                                    _auxiliaryAudioMuted(
                                                      clip.track,
                                                    ) ||
                                                    !_audioTrackIncludedBySolo(
                                                      clip.track,
                                                    ),
                                                onSelected:
                                                    widget.onAudioClipSelected,
                                                onChanged:
                                                    widget.onAudioClipChanged,
                                                onDelete:
                                                    widget.onDeleteAudioClip,
                                              ),
                                          Align(
                                            alignment: Alignment.bottomLeft,
                                            child: Padding(
                                              padding: EdgeInsets.only(
                                                top: layout.footerTop,
                                                left: 6,
                                              ),
                                              child: SizedBox(
                                                width: math.max(0, width - 12),
                                                child: Text(
                                                  widget.sequenceMode
                                                      ? 'Sequence ${formatSeconds(widget.duration)}  |  Source ${formatSeconds(widget.sourceDuration ?? 0)}  |  ${widget.segments.length} clips  |  Transitions ${_transitionCount()}  |  Detached A/V ${_detachedAudioCount()}'
                                                      : 'Source ${formatSeconds(widget.duration)}  |  Output ${formatSeconds(_totalOutputSeconds())}  |  Transitions ${_transitionCount()}  |  Detached A/V ${_detachedAudioCount()}',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: Theme.of(
                                                    context,
                                                  ).textTheme.labelSmall,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
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

  void _handlePointerDown(PointerDownEvent event) {
    if ((event.buttons & kPrimaryButton) == 0 || _activePointer != null) {
      return;
    }
    _activePointer = event.pointer;
    _pointerDownPosition = event.localPosition;
    _pointerDragging = false;
  }

  void _handlePointerMove(PointerMoveEvent event, double width) {
    if (_activePointer != event.pointer || _pointerDownPosition == null) {
      return;
    }
    if (!_pointerDragging) {
      if ((event.localPosition - _pointerDownPosition!).distance < 3) {
        return;
      }
      _pointerDragging = true;
      _startDrag(_pointerDownPosition!, width);
    }
    _updateDrag(event.localPosition.dx, width);
  }

  void _handlePointerEnd(PointerEvent event) {
    if (_activePointer != event.pointer) {
      return;
    }
    if (_pointerDragging) {
      _finishDrag();
      return;
    }
    _activePointer = null;
    _pointerDownPosition = null;
  }

  void _tap(Offset position, double width) {
    final track = _trackAt(position.dy);
    final hitIndex = _segmentIndexAt(position.dx, width, track);
    final seconds = _snapTimelineSeconds(
      _xToSeconds(position.dx, width),
      width,
    );
    final sourceSeconds = _sourceSecondsAtDisplay(seconds, hitIndex: hitIndex);
    if (hitIndex != null) {
      widget.onSegmentSelected(widget.segments[hitIndex].order);
    }
    if (widget.razorTool && hitIndex != null) {
      widget.onSplitAt?.call(sourceSeconds);
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
    final sourceSeconds = _sourceSecondsAtDisplay(seconds, hitIndex: hitIndex);
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
        widget.onSetMarkIn?.call(sourceSeconds);
      case _TimelineMenuAction.markOut:
        widget.onSetMarkOut?.call(sourceSeconds);
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
        widget.onAddMarkerAt?.call(sourceSeconds);
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
        widget.onSelectClipAt?.call(sourceSeconds);
      case _TimelineMenuAction.deselectClip:
        widget.onDeselectClip?.call();
      case _TimelineMenuAction.selectPreviousClip:
        widget.onSelectPreviousClip?.call();
      case _TimelineMenuAction.selectNextClip:
        widget.onSelectNextClip?.call();
      case _TimelineMenuAction.addEdit:
        widget.onAddEditAt?.call(sourceSeconds);
      case _TimelineMenuAction.addEditAllTracks:
        widget.onAddEditAllTracksAt?.call(sourceSeconds);
      case _TimelineMenuAction.rippleTrimStart:
        widget.onRippleTrimStartTo?.call(sourceSeconds);
      case _TimelineMenuAction.rippleTrimEnd:
        widget.onRippleTrimEndTo?.call(sourceSeconds);
      case _TimelineMenuAction.extendStart:
        widget.onExtendStartTo?.call(sourceSeconds);
      case _TimelineMenuAction.extendEnd:
        widget.onExtendEndTo?.call(sourceSeconds);
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
        widget.onSplitAt?.call(sourceSeconds);
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
        shortcut: 'Up / PageUp',
        enabled: widget.onJumpToPreviousEdit != null,
      ),
      _menuItem(
        Icons.vertical_align_bottom,
        'Next edit point',
        _TimelineMenuAction.nextEdit,
        shortcut: 'Down / PageDown',
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
        Icons.compare,
        'Cross Dissolve (A/V)',
        _TimelineMenuAction.applyVideoTransition,
        shortcut: 'Ctrl+D',
        enabled:
            segment != null &&
            segment.order > 1 &&
            !videoLocked &&
            !anyAudioLocked,
      ),
      _menuItem(
        Icons.graphic_eq,
        'Constant Power + Dissolve',
        _TimelineMenuAction.applyAudioTransition,
        shortcut: 'Ctrl+Shift+D',
        enabled:
            segment != null &&
            segment.order > 1 &&
            !videoLocked &&
            !anyAudioLocked,
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
      final placement = _placementForIndex(index);
      final startSeconds = _displayStartForTrack(segment, placement, track);
      final endSeconds = _displayEndForTrack(segment, placement, track);
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
        _dragOriginSegment = closestIndex == null
            ? null
            : widget.segments[closestIndex];
        _dragOriginSequenceStart = closestIndex == null
            ? null
            : _placementForIndex(closestIndex)?.sequenceStart;
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
      _dragOriginSegment = null;
      _dragOriginSequenceStart = null;
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
    final origin = _dragOriginSegment ?? current;
    final seconds = _snapTimelineSeconds(_xToSeconds(x, width), width);
    final sourceSeconds = widget.sequenceMode
        ? (origin.start +
                  (seconds - (_dragOriginSequenceStart ?? 0)) *
                      math.max(0.1, origin.playbackSpeed))
              .clamp(0.0, widget.sourceDuration ?? double.infinity)
              .toDouble()
        : seconds;

    HighlightSegment updated;
    if (track == _DragTrack.video) {
      if (edge == _DragEdge.start) {
        final maxStart = math.max(0.0, current.end - _minSegmentSeconds);
        final start = sourceSeconds.clamp(0.0, maxStart).toDouble();
        updated = current.copyWith(start: start);
      } else {
        final minEnd = math.min(
          widget.sourceDuration ?? widget.duration,
          current.start + _minSegmentSeconds,
        );
        final end = sourceSeconds
            .clamp(minEnd, widget.sourceDuration ?? widget.duration)
            .toDouble();
        updated = current.copyWith(end: end);
      }
    } else {
      if (edge == _DragEdge.start) {
        final maxStart = math.max(
          0.0,
          current.effectiveAudioEnd - _minSegmentSeconds,
        );
        final start = sourceSeconds.clamp(0.0, maxStart).toDouble();
        updated = current.copyWith(audioStart: start, audioLinked: false);
      } else {
        final minEnd = math.min(
          widget.sourceDuration ?? widget.duration,
          current.effectiveAudioStart + _minSegmentSeconds,
        );
        final end = sourceSeconds
            .clamp(minEnd, widget.sourceDuration ?? widget.duration)
            .toDouble();
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
      _dragOriginSegment = null;
      _dragOriginSequenceStart = null;
      _activePointer = null;
      _pointerDownPosition = null;
      _pointerDragging = false;
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
      final placement = _placementForIndex(index);
      final start = _displayStartForTrack(segment, placement, track);
      final end = _displayEndForTrack(segment, placement, track);
      final left = _secondsToX(start, width);
      final right = _secondsToX(end, width);
      if (x >= left && x <= right) {
        return index;
      }
    }
    return null;
  }

  _TimelinePlacement? _placementForIndex(int index) {
    if (!widget.sequenceMode || index < 0 || index >= widget.segments.length) {
      return null;
    }
    return _placements[index];
  }

  double _displayStartForTrack(
    HighlightSegment segment,
    _TimelinePlacement? placement,
    _DragTrack track,
  ) {
    if (placement == null) {
      return track == _DragTrack.video
          ? segment.start
          : segment.effectiveAudioStart;
    }
    return track == _DragTrack.video
        ? placement.sequenceStart
        : placement.audioStart;
  }

  double _displayEndForTrack(
    HighlightSegment segment,
    _TimelinePlacement? placement,
    _DragTrack track,
  ) {
    if (placement == null) {
      return track == _DragTrack.video
          ? segment.end
          : segment.effectiveAudioEnd;
    }
    return track == _DragTrack.video
        ? placement.sequenceEnd
        : placement.audioEnd;
  }

  double _sourceSecondsAtDisplay(double displaySeconds, {int? hitIndex}) {
    if (!widget.sequenceMode || widget.segments.isEmpty) {
      return displaySeconds;
    }
    final placements = _placements;
    _TimelinePlacement? placement;
    if (hitIndex != null && hitIndex >= 0 && hitIndex < placements.length) {
      placement = placements[hitIndex];
    } else {
      for (var index = placements.length - 1; index >= 0; index--) {
        final candidate = placements[index];
        if (displaySeconds >=
                candidate.sequenceStart - timecodeFrameDurationSeconds / 2 &&
            (displaySeconds <
                    candidate.sequenceEnd - timecodeFrameDurationSeconds / 2 ||
                index == placements.length - 1)) {
          placement = candidate;
          break;
        }
      }
    }
    if (placement == null) {
      return 0;
    }
    final localOutput = (displaySeconds - placement.sequenceStart)
        .clamp(0.0, placement.sequenceEnd - placement.sequenceStart)
        .toDouble();
    return (placement.segment.start + localOutput * placement.speed)
        .clamp(placement.segment.start, placement.segment.end)
        .toDouble();
  }

  double? _displaySecondsForSource(double sourceSeconds) {
    if (!widget.sequenceMode) {
      return sourceSeconds;
    }
    final placements = _placements;
    final preferred = placements.where(
      (placement) => placement.segment.order == widget.selectedSegmentOrder,
    );
    for (final placement in [...preferred, ...placements]) {
      if (sourceSeconds >= placement.segment.start &&
          sourceSeconds <= placement.segment.end) {
        return placement.sequenceStart +
            (sourceSeconds - placement.segment.start) / placement.speed;
      }
    }
    return null;
  }

  TimelineMarker? _markerAt(double x, double width) {
    TimelineMarker? closest;
    var closestDistance = double.infinity;
    for (final marker in widget.timelineMarkers) {
      final displaySeconds = _displaySecondsForSource(marker.seconds);
      if (displaySeconds == null) {
        continue;
      }
      final markerX = _secondsToX(displaySeconds, width);
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
    return widget.timelineMarkers.any((marker) {
      final seconds = _displaySecondsForSource(marker.seconds);
      return seconds != null && seconds > threshold;
    });
  }

  bool _hasPreviousMarker() {
    final threshold = widget.playheadSeconds - timecodeFrameDurationSeconds / 2;
    return widget.timelineMarkers.any((marker) {
      final seconds = _displaySecondsForSource(marker.seconds);
      return seconds != null && seconds < threshold;
    });
  }

  double _totalOutputSeconds() {
    return sequenceOutputDuration(widget.segments);
  }

  int _detachedAudioCount() {
    return widget.segments.where((segment) => !segment.audioLinked).length;
  }

  int _transitionCount() {
    var count = 0;
    for (var index = 1; index < widget.segments.length; index++) {
      if (effectiveTransitionOverlap(
            widget.segments[index - 1],
            widget.segments[index],
          ) >
          0) {
        count += 1;
      }
    }
    return count;
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
      final seconds = _displaySecondsForSource(widget.markIn!);
      if (seconds != null) {
        points.add(seconds);
      }
    }
    if (widget.markOut != null) {
      final seconds = _displaySecondsForSource(widget.markOut!);
      if (seconds != null) {
        points.add(seconds);
      }
    }
    for (final marker in widget.timelineMarkers) {
      if (marker.enabled) {
        final seconds = _displaySecondsForSource(marker.seconds);
        if (seconds != null) {
          points.add(seconds);
        }
      }
    }
    for (var index = 0; index < widget.segments.length; index++) {
      final segment = widget.segments[index];
      final placement = _placementForIndex(index);
      points
        ..add(_displayStartForTrack(segment, placement, _DragTrack.video))
        ..add(_displayEndForTrack(segment, placement, _DragTrack.video))
        ..add(_displayStartForTrack(segment, placement, _DragTrack.audio1))
        ..add(_displayEndForTrack(segment, placement, _DragTrack.audio1));
    }
    return points.toList();
  }
}

enum _OverlayDragMode { move, trimStart, trimEnd }

class _VideoOverlayBlock extends StatefulWidget {
  const _VideoOverlayBlock({
    required this.overlay,
    required this.duration,
    required this.canvasWidth,
    required this.top,
    required this.height,
    required this.selected,
    required this.locked,
    required this.trackVisible,
    required this.onSelected,
    required this.onChanged,
    required this.onDelete,
  });

  final VideoOverlayClip overlay;
  final double duration;
  final double canvasWidth;
  final double top;
  final double height;
  final bool selected;
  final bool locked;
  final bool trackVisible;
  final ValueChanged<String>? onSelected;
  final ValueChanged<VideoOverlayClip>? onChanged;
  final VoidCallback? onDelete;

  @override
  State<_VideoOverlayBlock> createState() => _VideoOverlayBlockState();
}

class _VideoOverlayBlockState extends State<_VideoOverlayBlock> {
  VideoOverlayClip? _origin;
  double _originGlobalX = 0;
  _OverlayDragMode? _mode;

  double get _pixelsPerSecond =>
      widget.duration <= 0 ? 1 : widget.canvasWidth / widget.duration;

  void _startDrag(DragStartDetails details, _OverlayDragMode mode) {
    if (widget.locked || widget.onChanged == null) {
      return;
    }
    widget.onSelected?.call(widget.overlay.id);
    _origin = widget.overlay;
    _originGlobalX = details.globalPosition.dx;
    _mode = mode;
  }

  void _updateDrag(DragUpdateDetails details) {
    final origin = _origin;
    final mode = _mode;
    final onChanged = widget.onChanged;
    if (origin == null || mode == null || onChanged == null) {
      return;
    }
    final delta = snapSecondsToFrame(
      (details.globalPosition.dx - _originGlobalX) / _pixelsPerSecond,
    );
    final minimum = timecodeFrameDurationSeconds;
    switch (mode) {
      case _OverlayDragMode.move:
        final duration = origin.timelineDuration;
        final start = snapSecondsToFrame(
          (origin.timelineStart + delta)
              .clamp(0.0, math.max(0.0, widget.duration - duration))
              .toDouble(),
        );
        onChanged(
          origin.copyWith(
            timelineStart: start,
            timelineEnd: snapSecondsToFrame(start + duration),
          ),
        );
      case _OverlayDragMode.trimStart:
        final maxStart = origin.timelineEnd - minimum;
        final start = snapSecondsToFrame(
          (origin.timelineStart + delta).clamp(0.0, maxStart).toDouble(),
        );
        final sourceStart = snapSecondsToFrame(
          (origin.sourceStart + (start - origin.timelineStart))
              .clamp(0.0, origin.sourceEnd - minimum)
              .toDouble(),
        );
        onChanged(
          origin.copyWith(
            timelineStart: start,
            sourceStart: sourceStart,
            audioGainKeyframes: windowAudioGainKeyframes(
              keyframes: origin.audioGainKeyframes,
              offset: start - origin.timelineStart,
              duration: origin.timelineEnd - start,
              fallback: origin.audioVolume,
            ),
          ),
        );
      case _OverlayDragMode.trimEnd:
        final end = snapSecondsToFrame(
          (origin.timelineEnd + delta)
              .clamp(origin.timelineStart + minimum, widget.duration)
              .toDouble(),
        );
        final sourceEnd = snapSecondsToFrame(
          math.max(
            origin.sourceStart + minimum,
            origin.sourceEnd + (end - origin.timelineEnd),
          ),
        );
        onChanged(
          origin.copyWith(
            timelineEnd: end,
            sourceEnd: sourceEnd,
            audioGainKeyframes: windowAudioGainKeyframes(
              keyframes: origin.audioGainKeyframes,
              offset: 0,
              duration: end - origin.timelineStart,
              fallback: origin.audioVolume,
            ),
          ),
        );
    }
  }

  void _endDrag(DragEndDetails details) {
    _origin = null;
    _mode = null;
  }

  Future<void> _showMenu(TapDownDetails details) async {
    widget.onSelected?.call(widget.overlay.id);
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        details.globalPosition.dx,
        details.globalPosition.dy,
        details.globalPosition.dx,
        details.globalPosition.dy,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'delete',
          enabled: !widget.locked,
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.delete_outline),
            title: Text('Delete V${widget.overlay.videoTrack} clip'),
            subtitle: const Text('Delete'),
          ),
        ),
      ],
    );
    if (action == 'delete') {
      widget.onDelete?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final overlay = widget.overlay;
    final colorScheme = Theme.of(context).colorScheme;
    final left = widget.duration <= 0
        ? 0.0
        : overlay.timelineStart / widget.duration * widget.canvasWidth;
    final width = math.max(
      18.0,
      overlay.timelineDuration /
          math.max(widget.duration, 0.001) *
          widget.canvasWidth,
    );
    final accent = _TimelinePainter._overlayClipColor;
    return Positioned(
      key: ValueKey('video-overlay-${overlay.id}'),
      left: left,
      top: widget.top,
      width: width,
      height: widget.height,
      child: Opacity(
        opacity: widget.trackVisible && overlay.enabled ? 1 : 0.38,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.onSelected?.call(overlay.id),
          onSecondaryTapDown: _showMenu,
          onHorizontalDragStart: (details) =>
              _startDrag(details, _OverlayDragMode.move),
          onHorizontalDragUpdate: _updateDrag,
          onHorizontalDragEnd: _endDrag,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: accent.withValues(alpha: widget.selected ? 0.96 : 0.78),
              border: Border.all(
                color: widget.selected ? Colors.white : accent,
                width: widget.selected ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  left: 7,
                  right: 7,
                  child: Row(
                    children: [
                      const Icon(
                        Icons.layers_outlined,
                        size: 13,
                        color: Color(0xFF071316),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'V${overlay.videoTrack} ${overlay.sourceName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: const Color(0xFF071316),
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!widget.locked) ...[
                  _OverlayTrimHandle(
                    alignment: Alignment.centerLeft,
                    cursor: SystemMouseCursors.resizeLeft,
                    onStart: (details) =>
                        _startDrag(details, _OverlayDragMode.trimStart),
                    onUpdate: _updateDrag,
                    onEnd: _endDrag,
                  ),
                  _OverlayTrimHandle(
                    alignment: Alignment.centerRight,
                    cursor: SystemMouseCursors.resizeRight,
                    onStart: (details) =>
                        _startDrag(details, _OverlayDragMode.trimEnd),
                    onUpdate: _updateDrag,
                    onEnd: _endDrag,
                  ),
                ],
                if (widget.locked)
                  Positioned(
                    right: 5,
                    top: 5,
                    child: Icon(
                      Icons.lock,
                      size: 12,
                      color: colorScheme.surface,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OverlayTrimHandle extends StatelessWidget {
  const _OverlayTrimHandle({
    required this.alignment,
    required this.cursor,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
  });

  final Alignment alignment;
  final MouseCursor cursor;
  final GestureDragStartCallback onStart;
  final GestureDragUpdateCallback onUpdate;
  final GestureDragEndCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: MouseRegion(
        cursor: cursor,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: onStart,
          onHorizontalDragUpdate: onUpdate,
          onHorizontalDragEnd: onEnd,
          child: Container(
            width: 7,
            margin: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ),
      ),
    );
  }
}

class _AudioAutomationDiamond extends StatelessWidget {
  const _AudioAutomationDiamond({required this.fraction});

  final double fraction;

  @override
  Widget build(BuildContext context) {
    final normalized = fraction.clamp(0.0, 1.0).toDouble();
    return IgnorePointer(
      child: Align(
        alignment: Alignment(normalized * 2 - 1, 0.78),
        child: Transform.rotate(
          angle: math.pi / 4,
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: const Color(0xFFFFD166),
              border: Border.all(color: const Color(0xFF231A05), width: 0.7),
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoOverlayAudioBlock extends StatelessWidget {
  const _VideoOverlayAudioBlock({
    required this.overlay,
    required this.duration,
    required this.canvasWidth,
    required this.top,
    required this.height,
    required this.selected,
    required this.locked,
    required this.trackMuted,
    required this.onSelected,
  });

  final VideoOverlayClip overlay;
  final double duration;
  final double canvasWidth;
  final double top;
  final double height;
  final bool selected;
  final bool locked;
  final bool trackMuted;
  final ValueChanged<String>? onSelected;

  @override
  Widget build(BuildContext context) {
    final left = duration <= 0
        ? 0.0
        : overlay.timelineStart / duration * canvasWidth;
    final width = math.max(
      18.0,
      overlay.timelineDuration / math.max(duration, 0.001) * canvasWidth,
    );
    final accent = _TimelinePainter._overlayAudioColor;
    final active =
        !trackMuted &&
        !overlay.muted &&
        (overlay.audioVolume > 0 ||
            overlay.audioGainKeyframes.any((keyframe) => keyframe.volume > 0));
    return Positioned(
      key: ValueKey('video-overlay-audio-${overlay.id}'),
      left: left,
      top: top,
      width: width,
      height: height,
      child: Opacity(
        opacity: active ? 1 : 0.4,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onSelected?.call(overlay.id),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: accent.withValues(alpha: selected ? 0.94 : 0.72),
              border: Border.all(
                color: selected ? Colors.white : accent,
                width: selected ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  left: 7,
                  right: 7,
                  child: Row(
                    children: [
                      Icon(
                        active ? Icons.graphic_eq : Icons.volume_off_outlined,
                        size: 13,
                        color: _TimelinePainter._clipTextColor,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'A${overlay.audioTrack} ${overlay.sourceName}${overlay.audioGainKeyframes.isEmpty ? '  ${(overlay.audioVolume * 100).round()}%' : '  VOL'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: _TimelinePainter._clipTextColor,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ),
                      if (locked)
                        const Icon(
                          Icons.lock,
                          size: 12,
                          color: _TimelinePainter._clipTextColor,
                        ),
                    ],
                  ),
                ),
                for (final keyframe in overlay.audioGainKeyframes)
                  _AudioAutomationDiamond(
                    fraction: overlay.timelineDuration <= 0
                        ? 0
                        : keyframe.time / overlay.timelineDuration,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StandaloneAudioBlock extends StatefulWidget {
  const _StandaloneAudioBlock({
    required this.clip,
    required this.duration,
    required this.canvasWidth,
    required this.top,
    required this.height,
    required this.selected,
    required this.locked,
    required this.trackMuted,
    required this.onSelected,
    required this.onChanged,
    required this.onDelete,
  });

  final AudioClip clip;
  final double duration;
  final double canvasWidth;
  final double top;
  final double height;
  final bool selected;
  final bool locked;
  final bool trackMuted;
  final ValueChanged<String>? onSelected;
  final ValueChanged<AudioClip>? onChanged;
  final VoidCallback? onDelete;

  @override
  State<_StandaloneAudioBlock> createState() => _StandaloneAudioBlockState();
}

class _StandaloneAudioBlockState extends State<_StandaloneAudioBlock> {
  AudioClip? _origin;
  double _originGlobalX = 0;
  _OverlayDragMode? _mode;

  double get _pixelsPerSecond =>
      widget.duration <= 0 ? 1 : widget.canvasWidth / widget.duration;

  void _startDrag(DragStartDetails details, _OverlayDragMode mode) {
    if (widget.locked || widget.onChanged == null) {
      return;
    }
    widget.onSelected?.call(widget.clip.id);
    _origin = widget.clip;
    _originGlobalX = details.globalPosition.dx;
    _mode = mode;
  }

  void _updateDrag(DragUpdateDetails details) {
    final origin = _origin;
    final mode = _mode;
    final onChanged = widget.onChanged;
    if (origin == null || mode == null || onChanged == null) {
      return;
    }
    final delta = snapSecondsToFrame(
      (details.globalPosition.dx - _originGlobalX) / _pixelsPerSecond,
    );
    final minimum = timecodeFrameDurationSeconds;
    switch (mode) {
      case _OverlayDragMode.move:
        final clipDuration = origin.timelineDuration;
        final start = snapSecondsToFrame(
          (origin.timelineStart + delta)
              .clamp(0.0, math.max(0.0, widget.duration - clipDuration))
              .toDouble(),
        );
        onChanged(
          origin.copyWith(
            timelineStart: start,
            timelineEnd: snapSecondsToFrame(start + clipDuration),
          ),
        );
      case _OverlayDragMode.trimStart:
        final maxStart = origin.timelineEnd - minimum;
        final start = snapSecondsToFrame(
          (origin.timelineStart + delta).clamp(0.0, maxStart).toDouble(),
        );
        final sourceStart = snapSecondsToFrame(
          (origin.sourceStart + (start - origin.timelineStart))
              .clamp(0.0, origin.sourceEnd - minimum)
              .toDouble(),
        );
        onChanged(
          origin.copyWith(
            timelineStart: start,
            sourceStart: sourceStart,
            gainKeyframes: windowAudioGainKeyframes(
              keyframes: origin.gainKeyframes,
              offset: start - origin.timelineStart,
              duration: origin.timelineEnd - start,
              fallback: origin.volume,
            ),
          ),
        );
      case _OverlayDragMode.trimEnd:
        final end = snapSecondsToFrame(
          (origin.timelineEnd + delta)
              .clamp(origin.timelineStart + minimum, widget.duration)
              .toDouble(),
        );
        final sourceEnd = snapSecondsToFrame(
          math.max(
            origin.sourceStart + minimum,
            origin.sourceEnd + (end - origin.timelineEnd),
          ),
        );
        onChanged(
          origin.copyWith(
            timelineEnd: end,
            sourceEnd: sourceEnd,
            gainKeyframes: windowAudioGainKeyframes(
              keyframes: origin.gainKeyframes,
              offset: 0,
              duration: end - origin.timelineStart,
              fallback: origin.volume,
            ),
          ),
        );
    }
  }

  void _endDrag(DragEndDetails details) {
    _origin = null;
    _mode = null;
  }

  Future<void> _showMenu(TapDownDetails details) async {
    widget.onSelected?.call(widget.clip.id);
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        details.globalPosition.dx,
        details.globalPosition.dy,
        details.globalPosition.dx,
        details.globalPosition.dy,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'delete',
          enabled: !widget.locked,
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.delete_outline),
            title: Text('Delete A${widget.clip.track} clip'),
            subtitle: const Text('Delete'),
          ),
        ),
      ],
    );
    if (action == 'delete') {
      widget.onDelete?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final clip = widget.clip;
    final left = widget.duration <= 0
        ? 0.0
        : clip.timelineStart / widget.duration * widget.canvasWidth;
    final width = math.max(
      18.0,
      clip.timelineDuration /
          math.max(widget.duration, 0.001) *
          widget.canvasWidth,
    );
    const accent = _TimelinePainter._standaloneAudioColor;
    final active =
        !widget.trackMuted &&
        clip.enabled &&
        !clip.muted &&
        (clip.volume > 0 ||
            clip.gainKeyframes.any((keyframe) => keyframe.volume > 0));
    return Positioned(
      key: ValueKey('audio-clip-${clip.id}'),
      left: left,
      top: widget.top,
      width: width,
      height: widget.height,
      child: Opacity(
        opacity: active ? 1 : 0.4,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.onSelected?.call(clip.id),
          onSecondaryTapDown: _showMenu,
          onHorizontalDragStart: (details) =>
              _startDrag(details, _OverlayDragMode.move),
          onHorizontalDragUpdate: _updateDrag,
          onHorizontalDragEnd: _endDrag,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: accent.withValues(alpha: widget.selected ? 0.96 : 0.78),
              border: Border.all(
                color: widget.selected ? Colors.white : accent,
                width: widget.selected ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  left: 7,
                  right: 7,
                  child: Row(
                    children: [
                      Icon(
                        active ? Icons.graphic_eq : Icons.volume_off_outlined,
                        size: 13,
                        color: _TimelinePainter._clipTextColor,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'A${clip.track} ${clip.sourceName}${clip.gainKeyframes.isEmpty ? '  ${(clip.volume * 100).round()}%' : '  VOL'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: _TimelinePainter._clipTextColor,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
                for (final keyframe in clip.gainKeyframes)
                  _AudioAutomationDiamond(
                    fraction: clip.timelineDuration <= 0
                        ? 0
                        : keyframe.time / clip.timelineDuration,
                  ),
                if (!widget.locked) ...[
                  _OverlayTrimHandle(
                    alignment: Alignment.centerLeft,
                    cursor: SystemMouseCursors.resizeLeft,
                    onStart: (details) =>
                        _startDrag(details, _OverlayDragMode.trimStart),
                    onUpdate: _updateDrag,
                    onEnd: _endDrag,
                  ),
                  _OverlayTrimHandle(
                    alignment: Alignment.centerRight,
                    cursor: SystemMouseCursors.resizeRight,
                    onStart: (details) =>
                        _startDrag(details, _OverlayDragMode.trimEnd),
                    onUpdate: _updateDrag,
                    onEnd: _endDrag,
                  ),
                ],
                if (widget.locked)
                  const Positioned(
                    right: 5,
                    top: 5,
                    child: Icon(
                      Icons.lock,
                      size: 12,
                      color: _TimelinePainter._clipTextColor,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TimelineTrackHeaders extends StatelessWidget {
  const _TimelineTrackHeaders({
    required this.layout,
    required this.segments,
    required this.videoOverlays,
    required this.audioClips,
    required this.activeVideoTrackCount,
    required this.activeAudioTrackCount,
    required this.targetedVideoOverlayTrack,
    required this.targetedOverlayAudioTrack,
    required this.overlayTargeted,
    required this.videoTargeted,
    required this.audio1Targeted,
    required this.audio2Targeted,
    required this.audio3Targeted,
    required this.videoLocked,
    required this.overlayLocked,
    required this.overlayVisible,
    required this.lockedVideoOverlayTracks,
    required this.hiddenVideoOverlayTracks,
    required this.audio1Locked,
    required this.audio2Locked,
    required this.audio3Locked,
    required this.lockedAuxiliaryAudioTracks,
    required this.mutedAuxiliaryAudioTracks,
    required this.soloAudioTracks,
    required this.onToggleVideoTarget,
    required this.onToggleOverlayTarget,
    required this.onToggleOverlayTargetAt,
    required this.onToggleAudio1Target,
    required this.onToggleAudio2Target,
    required this.onToggleAudio3Target,
    required this.onToggleVideoLock,
    required this.onToggleOverlayLock,
    required this.onToggleOverlayLockAt,
    required this.onToggleOverlayVisibility,
    required this.onToggleOverlayVisibilityAt,
    required this.onToggleAudio1Lock,
    required this.onToggleAudio2Lock,
    required this.onToggleAudio3Lock,
    required this.onToggleAuxiliaryAudioLockAt,
    required this.onToggleAudioSoloAt,
    required this.onToggleAudio1,
    required this.onToggleAudio2,
    required this.onToggleAudio3,
    required this.onToggleOverlayAudioTargetAt,
    required this.onToggleOverlayAudioAt,
  });

  final _TimelineLayout layout;
  final List<HighlightSegment> segments;
  final List<VideoOverlayClip> videoOverlays;
  final List<AudioClip> audioClips;
  final int activeVideoTrackCount;
  final int activeAudioTrackCount;
  final int targetedVideoOverlayTrack;
  final int targetedOverlayAudioTrack;
  final bool overlayTargeted;
  final bool videoTargeted;
  final bool audio1Targeted;
  final bool audio2Targeted;
  final bool audio3Targeted;
  final bool videoLocked;
  final bool overlayLocked;
  final bool overlayVisible;
  final Set<int> lockedVideoOverlayTracks;
  final Set<int> hiddenVideoOverlayTracks;
  final bool audio1Locked;
  final bool audio2Locked;
  final bool audio3Locked;
  final Set<int> lockedAuxiliaryAudioTracks;
  final Set<int> mutedAuxiliaryAudioTracks;
  final Set<int> soloAudioTracks;
  final VoidCallback? onToggleVideoTarget;
  final VoidCallback? onToggleOverlayTarget;
  final ValueChanged<int>? onToggleOverlayTargetAt;
  final VoidCallback? onToggleAudio1Target;
  final VoidCallback? onToggleAudio2Target;
  final VoidCallback? onToggleAudio3Target;
  final VoidCallback? onToggleVideoLock;
  final VoidCallback? onToggleOverlayLock;
  final ValueChanged<int>? onToggleOverlayLockAt;
  final VoidCallback? onToggleOverlayVisibility;
  final ValueChanged<int>? onToggleOverlayVisibilityAt;
  final VoidCallback? onToggleAudio1Lock;
  final VoidCallback? onToggleAudio2Lock;
  final VoidCallback? onToggleAudio3Lock;
  final ValueChanged<int>? onToggleAuxiliaryAudioLockAt;
  final ValueChanged<int>? onToggleAudioSoloAt;
  final VoidCallback? onToggleAudio1;
  final VoidCallback? onToggleAudio2;
  final VoidCallback? onToggleAudio3;
  final ValueChanged<int>? onToggleOverlayAudioTargetAt;
  final ValueChanged<int>? onToggleOverlayAudioAt;

  bool get _audio1Enabled =>
      (soloAudioTracks.isEmpty || soloAudioTracks.contains(1)) &&
      (segments.isEmpty ||
          segments.any(
            (segment) => !segment.audioMuted && segment.audioChannel1Enabled,
          ));

  bool get _audio2Enabled =>
      (soloAudioTracks.isEmpty || soloAudioTracks.contains(2)) &&
      (segments.isEmpty ||
          segments.any(
            (segment) => !segment.audioMuted && segment.audioChannel2Enabled,
          ));

  bool _overlayAudioEnabledFor(int track) {
    if (mutedAuxiliaryAudioTracks.contains(track) ||
        (soloAudioTracks.isNotEmpty && !soloAudioTracks.contains(track))) {
      return false;
    }
    final overlays = videoOverlays.where(
      (overlay) => overlay.audioTrack == track,
    );
    final standalone = audioClips.where((clip) => clip.track == track);
    return (overlays.isEmpty && standalone.isEmpty) ||
        overlays.any((overlay) => !overlay.muted && overlay.audioVolume > 0) ||
        standalone.any(
          (clip) => clip.enabled && !clip.muted && clip.volume > 0,
        );
  }

  void _toggleOverlayTarget(int track) {
    final callback = onToggleOverlayTargetAt;
    if (callback != null) {
      callback(track);
    } else {
      onToggleOverlayTarget?.call();
    }
  }

  bool _overlayTrackLocked(int track) =>
      lockedVideoOverlayTracks.contains(track) ||
      (lockedVideoOverlayTracks.isEmpty && overlayLocked);

  bool _overlayTrackVisible(int track) =>
      !hiddenVideoOverlayTracks.contains(track) &&
      (hiddenVideoOverlayTracks.isNotEmpty || overlayVisible);

  bool _auxiliaryTrackLocked(int track) =>
      lockedAuxiliaryAudioTracks.contains(track) ||
      (lockedAuxiliaryAudioTracks.isEmpty && audio3Locked);

  void _toggleOverlayLock(int track) {
    final callback = onToggleOverlayLockAt;
    if (callback != null) {
      callback(track);
    } else {
      onToggleOverlayLock?.call();
    }
  }

  void _toggleOverlayVisibility(int track) {
    final callback = onToggleOverlayVisibilityAt;
    if (callback != null) {
      callback(track);
    } else {
      onToggleOverlayVisibility?.call();
    }
  }

  void _toggleAuxiliaryAudioLock(int track) {
    final callback = onToggleAuxiliaryAudioLockAt;
    if (callback != null) {
      callback(track);
    } else {
      onToggleAudio3Lock?.call();
    }
  }

  void _toggleOverlayAudioTarget(int track) {
    final callback = onToggleOverlayAudioTargetAt;
    if (callback != null) {
      callback(track);
    } else if (track == 3) {
      onToggleAudio3Target?.call();
    }
  }

  void _toggleOverlayAudio(int track) {
    final callback = onToggleOverlayAudioAt;
    if (callback != null) {
      callback(track);
    } else {
      onToggleAudio3?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return KeyedSubtree(
      key: const Key('timeline-track-headers'),
      child: DecoratedBox(
        decoration: BoxDecoration(color: colorScheme.surfaceContainerHighest),
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: layout.rulerHeight,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  border: Border(
                    bottom: BorderSide(color: colorScheme.outline),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.view_timeline_outlined,
                      size: 15,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'SEQUENCE 01',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      '30p',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            for (var track = activeVideoTrackCount; track >= 2; track -= 1)
              _TrackHeaderLane(
                key: Key('track-header-v$track'),
                top: layout.videoTrackTop(track),
                height: layout.laneHeight,
                patchLabel: 'V$track',
                trackLabel: track == 2 ? 'Overlay / B-roll' : 'Video $track',
                accent: _TimelinePainter._overlayClipColor,
                targeted: overlayTargeted && targetedVideoOverlayTrack == track,
                locked: _overlayTrackLocked(track),
                mediaEnabled: _overlayTrackVisible(track),
                mediaIcon: _overlayTrackVisible(track)
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                mediaTooltip: _overlayTrackVisible(track)
                    ? 'V$track 숨기기'
                    : 'V$track 표시',
                onToggleTarget: () => _toggleOverlayTarget(track),
                onToggleLock: () => _toggleOverlayLock(track),
                onToggleMedia: () => _toggleOverlayVisibility(track),
              ),
            _TrackHeaderLane(
              key: const Key('track-header-v1'),
              top: layout.videoTop,
              height: layout.laneHeight,
              patchLabel: 'V1',
              trackLabel: 'Video 1',
              accent: _TimelinePainter._videoClipColor,
              targeted: videoTargeted,
              locked: videoLocked,
              mediaEnabled: true,
              mediaIcon: Icons.videocam_outlined,
              mediaTooltip: '비디오 트랙',
              onToggleTarget: onToggleVideoTarget,
              onToggleLock: onToggleVideoLock,
            ),
            _TrackHeaderLane(
              key: const Key('track-header-a1'),
              top: layout.audio1Top,
              height: layout.laneHeight,
              patchLabel: 'A1',
              trackLabel: 'Audio 1',
              accent: _TimelinePainter._audioClipColor,
              targeted: audio1Targeted,
              locked: audio1Locked,
              mediaEnabled: _audio1Enabled,
              mediaIcon: _audio1Enabled
                  ? Icons.volume_up_outlined
                  : Icons.volume_off_outlined,
              mediaTooltip: _audio1Enabled ? 'A1 전체 비활성화' : 'A1 전체 활성화',
              onToggleTarget: onToggleAudio1Target,
              onToggleLock: onToggleAudio1Lock,
              onToggleMedia: audio1Locked ? null : onToggleAudio1,
              soloed: soloAudioTracks.contains(1),
              onToggleSolo: onToggleAudioSoloAt == null
                  ? null
                  : () => onToggleAudioSoloAt!(1),
            ),
            _TrackHeaderLane(
              key: const Key('track-header-a2'),
              top: layout.audio2Top,
              height: layout.laneHeight,
              patchLabel: 'A2',
              trackLabel: 'Audio 2',
              accent: _TimelinePainter._audioClipColor,
              targeted: audio2Targeted,
              locked: audio2Locked,
              mediaEnabled: _audio2Enabled,
              mediaIcon: _audio2Enabled
                  ? Icons.volume_up_outlined
                  : Icons.volume_off_outlined,
              mediaTooltip: _audio2Enabled ? 'A2 전체 비활성화' : 'A2 전체 활성화',
              onToggleTarget: onToggleAudio2Target,
              onToggleLock: onToggleAudio2Lock,
              onToggleMedia: audio2Locked ? null : onToggleAudio2,
              soloed: soloAudioTracks.contains(2),
              onToggleSolo: onToggleAudioSoloAt == null
                  ? null
                  : () => onToggleAudioSoloAt!(2),
            ),
            for (var track = 3; track <= activeAudioTrackCount; track += 1)
              _TrackHeaderLane(
                key: Key('track-header-a$track'),
                top: layout.audioTrackTop(track),
                height: layout.laneHeight,
                patchLabel: 'A$track',
                trackLabel: track == 3 ? 'Audio 3 / B-roll' : 'Audio $track',
                accent: _TimelinePainter._overlayAudioColor,
                targeted:
                    targetedOverlayAudioTrack == track &&
                    (track != 3 || audio3Targeted),
                locked: _auxiliaryTrackLocked(track),
                mediaEnabled: _overlayAudioEnabledFor(track),
                mediaIcon: _overlayAudioEnabledFor(track)
                    ? Icons.volume_up_outlined
                    : Icons.volume_off_outlined,
                mediaTooltip: _overlayAudioEnabledFor(track)
                    ? 'A$track 전체 비활성화'
                    : 'A$track 전체 활성화',
                onToggleTarget: () => _toggleOverlayAudioTarget(track),
                onToggleLock: () => _toggleAuxiliaryAudioLock(track),
                onToggleMedia: _auxiliaryTrackLocked(track)
                    ? null
                    : () => _toggleOverlayAudio(track),
                soloed: soloAudioTracks.contains(track),
                onToggleSolo: onToggleAudioSoloAt == null
                    ? null
                    : () => onToggleAudioSoloAt!(track),
              ),
            Positioned(
              left: 8,
              right: 8,
              top: layout.footerTop + 5,
              child: Text(
                'V1-V$activeVideoTrackCount / A1-A$activeAudioTrackCount  ·  30p NDF',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrackHeaderLane extends StatelessWidget {
  const _TrackHeaderLane({
    super.key,
    required this.top,
    required this.height,
    required this.patchLabel,
    required this.trackLabel,
    required this.accent,
    required this.targeted,
    required this.locked,
    required this.mediaEnabled,
    required this.mediaIcon,
    required this.mediaTooltip,
    required this.onToggleTarget,
    required this.onToggleLock,
    this.onToggleMedia,
    this.soloed = false,
    this.onToggleSolo,
  });

  final double top;
  final double height;
  final String patchLabel;
  final String trackLabel;
  final Color accent;
  final bool targeted;
  final bool locked;
  final bool mediaEnabled;
  final IconData mediaIcon;
  final String mediaTooltip;
  final VoidCallback? onToggleTarget;
  final VoidCallback? onToggleLock;
  final VoidCallback? onToggleMedia;
  final bool soloed;
  final VoidCallback? onToggleSolo;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Positioned(
      left: 0,
      right: 0,
      top: top,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: accent.withValues(alpha: targeted ? 0.10 : 0.035),
          border: Border(
            left: BorderSide(
              color: targeted ? accent : Colors.transparent,
              width: 3,
            ),
            bottom: BorderSide(
              color: colorScheme.outline.withValues(alpha: 0.70),
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(5, 2, 4, 2),
          child: Row(
            children: [
              Tooltip(
                message: '$patchLabel 편집 타깃',
                child: InkWell(
                  onTap: onToggleTarget,
                  borderRadius: BorderRadius.circular(2),
                  child: Container(
                    width: 30,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: targeted
                          ? accent.withValues(alpha: 0.88)
                          : colorScheme.surface,
                      border: Border.all(
                        color: targeted ? accent : colorScheme.outline,
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Text(
                      patchLabel,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: targeted
                            ? const Color(0xFF11140F)
                            : colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  trackLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: locked
                        ? colorScheme.onSurfaceVariant
                        : colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (onToggleSolo != null)
                _TrackHeaderSoloButton(
                  key: Key('track-solo-${patchLabel.toLowerCase()}'),
                  trackLabel: patchLabel,
                  active: soloed,
                  onPressed: onToggleSolo,
                ),
              _TrackHeaderIconButton(
                tooltip: mediaTooltip,
                icon: mediaIcon,
                active: mediaEnabled,
                onPressed: onToggleMedia,
              ),
              _TrackHeaderIconButton(
                tooltip: locked ? '트랙 잠금 해제' : '트랙 잠금',
                icon: locked ? Icons.lock : Icons.lock_open,
                active: locked,
                onPressed: onToggleLock,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrackHeaderSoloButton extends StatelessWidget {
  const _TrackHeaderSoloButton({
    super.key,
    required this.trackLabel,
    required this.active,
    required this.onPressed,
  });

  final String trackLabel;
  final bool active;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final activeColor = colorScheme.tertiary;
    final actionLabel = active ? 'Solo 해제' : '이 트랙만 듣기 (Solo)';
    return Semantics(
      button: true,
      toggled: active,
      label: '$trackLabel $actionLabel',
      excludeSemantics: true,
      child: Tooltip(
        message: '$trackLabel $actionLabel',
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(2),
          child: Container(
            width: 21,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active
                  ? activeColor.withValues(alpha: 0.18)
                  : Colors.transparent,
              border: Border.all(
                color: active
                    ? activeColor
                    : colorScheme.outline.withValues(alpha: 0.75),
              ),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              'S',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: active ? activeColor : colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TrackHeaderIconButton extends StatelessWidget {
  const _TrackHeaderIconButton({
    required this.tooltip,
    required this.icon,
    required this.active,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final bool active;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 24,
      height: 22,
      child: IconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        onPressed: onPressed,
        icon: Icon(
          icon,
          size: 15,
          color: active ? colorScheme.primary : colorScheme.onSurfaceVariant,
        ),
      ),
    );
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
    required this.timelineThumbnails,
    required this.activeIndex,
    required this.activeEdge,
    required this.activeTrack,
    required this.videoTrackLocked,
    required this.audioTrack1Locked,
    required this.audioTrack2Locked,
    required this.colorScheme,
    required this.sequenceMode,
    required this.sourceDuration,
  });

  static const double _handleVisualWidth =
      _TimelineEditorState._handleVisualWidth;
  static const Color _overlayClipColor = Color(0xFF62B7C8);
  static const Color _videoClipColor = Color(0xFF79C98D);
  static const Color _videoClipActiveColor = Color(0xFF9BE3A9);
  static const Color _audioClipColor = Color(0xFFE7A66A);
  static const Color _audioClipActiveColor = Color(0xFFF4BE84);
  static const Color _overlayAudioColor = Color(0xFFD18A63);
  static const Color _standaloneAudioColor = Color(0xFFF2B84B);
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
  final Map<int, ui.Image> timelineThumbnails;
  final int? activeIndex;
  final _DragEdge? activeEdge;
  final _DragTrack? activeTrack;
  final bool videoTrackLocked;
  final bool audioTrack1Locked;
  final bool audioTrack2Locked;
  final ColorScheme colorScheme;
  final bool sequenceMode;
  final double sourceDuration;

  List<_TimelinePlacement> get placements => _buildTimelinePlacements(segments);

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(2);
    for (var track = layout.activeVideoTracks; track >= 2; track -= 1) {
      _drawTrack(
        canvas,
        size,
        layout.videoTrackTop(track),
        radius,
        _overlayClipColor,
      );
    }
    _drawTrack(canvas, size, layout.videoTrackTop(1), radius, _videoClipColor);
    for (var track = 1; track <= layout.activeAudioTracks; track += 1) {
      _drawTrack(
        canvas,
        size,
        layout.audioTrackTop(track),
        radius,
        track <= 2 ? _audioClipColor : _overlayAudioColor,
      );
    }
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
    Color accent,
  ) {
    final rect = Rect.fromLTWH(0, top, size.width, layout.laneHeight);
    final track = RRect.fromRectAndRadius(rect, radius);
    canvas.drawRRect(
      track,
      Paint()
        ..color = Color.alphaBlend(
          accent.withValues(alpha: 0.025),
          colorScheme.surfaceContainerHighest,
        ),
    );
    canvas.drawRRect(
      track,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            colorScheme.onSurface.withValues(alpha: 0.025),
            colorScheme.surface.withValues(alpha: 0.06),
          ],
        ).createShader(rect),
    );
    canvas.drawRRect(
      track,
      Paint()
        ..color = colorScheme.outline.withValues(alpha: 0.62)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.7,
    );
    canvas.drawLine(
      Offset(0, top + layout.laneHeight / 2),
      Offset(size.width, top + layout.laneHeight / 2),
      Paint()
        ..color = colorScheme.onSurfaceVariant.withValues(alpha: 0.06)
        ..strokeWidth = 1,
    );
  }

  void _drawInOutRange(Canvas canvas, Size size) {
    final inPoint = markIn == null ? null : _displaySecondsForSource(markIn!);
    final outPoint = markOut == null
        ? null
        : _displaySecondsForSource(markOut!);
    if (inPoint == null || outPoint == null || outPoint <= inPoint) {
      return;
    }
    final left = _secondsToX(inPoint, size.width);
    final right = _secondsToX(outPoint, size.width);
    final rangeRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        left,
        layout.overlayTop - 7,
        math.max(2, right - left),
        layout.trackBottom - layout.overlayTop + 14,
      ),
      Radius.circular(6),
    );
    canvas.drawRRect(
      rangeRect,
      Paint()..color = colorScheme.tertiary.withValues(alpha: 0.07),
    );
    canvas.drawRect(
      Rect.fromLTWH(left, layout.overlayTop - 5, math.max(2, right - left), 3),
      Paint()..color = colorScheme.tertiary.withValues(alpha: 0.88),
    );
  }

  void _drawTicks(Canvas canvas, Size size) {
    final rulerRect = Rect.fromLTWH(0, 0, size.width, layout.rulerHeight);
    canvas.drawRect(
      rulerRect,
      Paint()..color = colorScheme.surface.withValues(alpha: 0.78),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, layout.rulerHeight - 1, size.width, 1),
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
      final top = isMajor ? layout.rulerHeight - 6 : layout.rulerHeight - 2;
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
      final placement = sequenceMode ? placements[index] : null;
      final videoStart = placement?.sequenceStart ?? segment.start;
      final videoEnd = placement?.sequenceEnd ?? segment.end;
      final isActive =
          activeIndex == index || selectedSegmentOrder == segment.order;

      _drawClipBlock(
        canvas,
        size,
        top: layout.videoTop,
        start: videoStart,
        end: videoEnd,
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
        hasVideoEffects:
            segment.motionKeyframes.isNotEmpty ||
            (segment.videoOpacity - 1).abs() > 0.0001 ||
            (segment.videoScale - 1).abs() > 0.0001 ||
            segment.videoPositionX.abs() > 0.0001 ||
            segment.videoPositionY.abs() > 0.0001 ||
            segment.videoRotation.abs() > 0.0001 ||
            segment.videoFadeIn > 0 ||
            segment.videoFadeOut > 0 ||
            segment.colorBrightness.abs() > 0.0001 ||
            (segment.colorContrast - 1).abs() > 0.0001 ||
            (segment.colorSaturation - 1).abs() > 0.0001,
        motionKeyframePositions: [
          for (final keyframe in segment.motionKeyframes)
            videoStart +
                keyframe.time * (sequenceMode ? 1.0 : segment.playbackSpeed),
        ],
        thumbnails: timelineThumbnailSampleFrames(segment)
            .map((frame) => timelineThumbnails[frame])
            .whereType<ui.Image>()
            .toList(),
      );
      _drawFadeOverlay(canvas, size, segment, placement);

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
        placement: placement,
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
        placement: placement,
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
        _drawPanIndicator(canvas, size, segment, placement);
      }
      if (placement != null) {
        _drawTransitionOverlay(canvas, size, placement);
      }
    }
  }

  bool _isAudioTrack(_DragTrack? track) =>
      track == _DragTrack.audio1 || track == _DragTrack.audio2;

  void _drawAudioChannelBlock(
    Canvas canvas,
    Size size, {
    required HighlightSegment segment,
    required _TimelinePlacement? placement,
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
    final displayStart = placement?.audioStart ?? segment.effectiveAudioStart;
    final displayEnd = placement?.audioEnd ?? segment.effectiveAudioEnd;
    _drawClipBlock(
      canvas,
      size,
      top: top,
      start: displayStart,
      end: displayEnd,
      waveformSourceStart: segment.effectiveAudioStart,
      waveformSourceEnd: segment.effectiveAudioEnd,
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
      audioGainKeyframePositions: [
        for (final keyframe in segment.audioGainKeyframes)
          displayStart +
              keyframe.time * (sequenceMode ? 1.0 : segment.playbackSpeed),
      ],
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
    double? waveformSourceStart,
    double? waveformSourceEnd,
    bool disabledPattern = false,
    bool hasVideoEffects = false,
    List<double> motionKeyframePositions = const [],
    List<double> audioGainKeyframePositions = const [],
    List<ui.Image> thumbnails = const [],
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
    if (track == _DragTrack.video &&
        thumbnails.isNotEmpty &&
        rect.width >= 20) {
      _drawVideoThumbnailStrip(
        canvas,
        rrect,
        rect,
        thumbnails,
        enabled: !disabledPattern,
      );
    }
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
      _drawAudioPresence(
        canvas,
        rect,
        waveformSourceStart ?? start,
        waveformSourceEnd ?? end,
      );
    }
    _drawClipTimecodeLabel(
      canvas,
      rect,
      label,
      start,
      end,
      track,
      hasThumbnail: track == _DragTrack.video && thumbnails.isNotEmpty,
      hasVideoEffects: hasVideoEffects,
    );
    if (hasVideoEffects && track == _DragTrack.video && rect.width >= 72) {
      _drawFxBadge(canvas, rect);
    }
    if (track == _DragTrack.video && motionKeyframePositions.isNotEmpty) {
      _drawMotionKeyframeMarkers(canvas, size, rect, motionKeyframePositions);
    }
    if (track != _DragTrack.video && audioGainKeyframePositions.isNotEmpty) {
      _drawAudioGainKeyframeMarkers(
        canvas,
        size,
        rect,
        audioGainKeyframePositions,
      );
    }
    final effectiveBorder = handlesActive ? colorScheme.primary : border;
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = effectiveBorder.withValues(alpha: handlesActive ? 1.0 : 0.48)
        ..style = PaintingStyle.stroke
        ..strokeWidth = handlesActive ? 1.5 : 0.7,
    );

    if (handlesActive) {
      final handlePaint = Paint()
        ..color = colorScheme.primary
        ..strokeWidth = _handleVisualWidth;
      for (final handleX in [left, right]) {
        canvas.drawLine(
          Offset(handleX, top),
          Offset(handleX, top + layout.laneHeight),
          handlePaint,
        );
      }
    }
  }

  void _drawVideoThumbnailStrip(
    Canvas canvas,
    RRect clip,
    Rect rect,
    List<ui.Image> images, {
    required bool enabled,
  }) {
    final tileWidth = math.max(36.0, rect.height * 16 / 9);
    final tileCount = math.max(1, (rect.width / tileWidth).ceil());
    canvas.save();
    canvas.clipRRect(clip);
    for (var index = 0; index < tileCount; index++) {
      final left = rect.left + index * tileWidth;
      final imageIndex = images.length == 1
          ? 0
          : ((index / math.max(1, tileCount - 1)) * (images.length - 1))
                .round()
                .clamp(0, images.length - 1);
      paintImage(
        canvas: canvas,
        rect: Rect.fromLTWH(
          left,
          rect.top,
          math.min(tileWidth, rect.right - left),
          rect.height,
        ),
        image: images[imageIndex],
        fit: BoxFit.cover,
        alignment: Alignment.center,
        opacity: enabled ? 0.82 : 0.28,
        filterQuality: FilterQuality.low,
      );
    }
    canvas.drawRect(
      Rect.fromLTWH(rect.left, rect.top, rect.width, 14),
      Paint()..color = Colors.black.withValues(alpha: 0.46),
    );
    if (rect.height >= 30) {
      canvas.drawRect(
        Rect.fromLTWH(rect.left, rect.bottom - 12, rect.width, 12),
        Paint()..color = Colors.black.withValues(alpha: 0.40),
      );
    }
    canvas.restore();
  }

  void _drawFxBadge(Canvas canvas, Rect rect) {
    final badgeRect = Rect.fromLTWH(rect.right - 25, rect.top + 3, 21, 13);
    canvas.drawRRect(
      RRect.fromRectAndRadius(badgeRect, const Radius.circular(3)),
      Paint()..color = colorScheme.primary.withValues(alpha: 0.88),
    );
    final painter = TextPainter(
      text: TextSpan(
        text: 'FX',
        style: TextStyle(
          color: colorScheme.onPrimary,
          fontSize: 8,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(
        badgeRect.center.dx - painter.width / 2,
        badgeRect.center.dy - painter.height / 2,
      ),
    );
  }

  void _drawMotionKeyframeMarkers(
    Canvas canvas,
    Size size,
    Rect rect,
    List<double> positions,
  ) {
    final fill = Paint()..color = const Color(0xFFFFD166);
    final stroke = Paint()
      ..color = Colors.black.withValues(alpha: 0.78)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    for (final position in positions) {
      final x = _secondsToX(
        position,
        size.width,
      ).clamp(rect.left + 4, rect.right - 4).toDouble();
      final center = Offset(x, rect.bottom - 8);
      final path = Path()
        ..moveTo(center.dx, center.dy - 4)
        ..lineTo(center.dx + 4, center.dy)
        ..lineTo(center.dx, center.dy + 4)
        ..lineTo(center.dx - 4, center.dy)
        ..close();
      canvas.drawPath(path, fill);
      canvas.drawPath(path, stroke);
    }
  }

  void _drawAudioGainKeyframeMarkers(
    Canvas canvas,
    Size size,
    Rect rect,
    List<double> positions,
  ) {
    final fill = Paint()..color = const Color(0xFFFFD166);
    final stroke = Paint()
      ..color = Colors.black.withValues(alpha: 0.78)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    for (final position in positions) {
      final x = _secondsToX(
        position,
        size.width,
      ).clamp(rect.left + 4, rect.right - 4).toDouble();
      final center = Offset(x, rect.bottom - 7);
      final path = Path()
        ..moveTo(center.dx, center.dy - 3.5)
        ..lineTo(center.dx + 3.5, center.dy)
        ..lineTo(center.dx, center.dy + 3.5)
        ..lineTo(center.dx - 3.5, center.dy)
        ..close();
      canvas.drawPath(path, fill);
      canvas.drawPath(path, stroke);
    }
  }

  void _drawVideoPresence(Canvas canvas, Rect rect) {
    if (rect.width < 18) {
      return;
    }
    final paint = Paint()
      ..color = _clipTextColor.withValues(alpha: 0.18)
      ..strokeWidth = 0.8;
    final top = rect.bottom - 9;
    final bottom = rect.bottom - 3;
    for (var x = rect.left + 12; x < rect.right - 4; x += 16) {
      canvas.drawLine(Offset(x, top), Offset(x, bottom), paint);
    }
  }

  void _drawAudioPresence(Canvas canvas, Rect rect, double start, double end) {
    if (rect.width < 18) {
      return;
    }
    final centerY = rect.center.dy + 3;
    canvas.drawLine(
      Offset(rect.left + 7, centerY),
      Offset(rect.right - 7, centerY),
      Paint()
        ..color = _clipTextColor.withValues(alpha: 0.12)
        ..strokeWidth = 0.8,
    );
    final wavePaint = Paint()
      ..color = _clipTextColor.withValues(alpha: 0.34)
      ..strokeWidth = 0.8;
    final step = math.max(2.0, rect.width / 180);
    for (var x = rect.left + 6; x < rect.right - 5; x += step) {
      final ratio = ((x - rect.left) / math.max(1.0, rect.width))
          .clamp(0.0, 1.0)
          .toDouble();
      final sourceSeconds = start + (end - start) * ratio;
      final peak = waveform.isEmpty || sourceDuration <= 0
          ? 0.32 + 0.18 * math.sin(ratio * math.pi * 24).abs()
          : waveform[(sourceSeconds / sourceDuration * (waveform.length - 1))
                    .round()
                    .clamp(0, waveform.length - 1)
                    .toInt()]
                .clamp(0.0, 1.0)
                .toDouble();
      final halfHeight = math.max(1.0, peak * (rect.height * 0.34));
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
    _DragTrack track, {
    bool hasThumbnail = false,
    bool hasVideoEffects = false,
  }) {
    if (rect.width < 28) {
      return;
    }
    final timeText = '${formatSeconds(start)} - ${formatSeconds(end)}';
    final compactLabel = rect.width >= 92 ? label : label.split(' ').first;
    final textColor = hasThumbnail ? Colors.white : _clipTextColor;
    final labelPainter = TextPainter(
      text: TextSpan(
        text: compactLabel,
        style: TextStyle(
          color: textColor.withValues(alpha: 0.94),
          fontSize: rect.width >= 92 ? 9 : 8,
          fontWeight: FontWeight.w800,
        ),
      ),
      maxLines: 1,
      ellipsis: '…',
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: math.max(0, rect.width - (hasVideoEffects ? 40 : 12)));
    labelPainter.paint(
      canvas,
      Offset(
        rect.left + 6,
        rect.height >= 30
            ? rect.top + 3
            : rect.center.dy - labelPainter.height / 2,
      ),
    );
    if (rect.height < 30 || rect.width < 96) {
      return;
    }
    final timePainter = TextPainter(
      text: TextSpan(
        text: rect.width >= 190
            ? timeText
            : formatSeconds(track == _DragTrack.video ? start : end),
        style: TextStyle(
          color: textColor.withValues(alpha: 0.82),
          fontSize: 8,
          fontWeight: FontWeight.w600,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      maxLines: 1,
      ellipsis: '…',
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: math.max(0, rect.width - 12));
    timePainter.paint(
      canvas,
      Offset(rect.left + 6, rect.bottom - timePainter.height - 2),
    );
  }

  void _drawPanIndicator(
    Canvas canvas,
    Size size,
    HighlightSegment segment,
    _TimelinePlacement? placement,
  ) {
    final left = _secondsToX(
      placement?.audioStart ?? segment.effectiveAudioStart,
      size.width,
    );
    final right = _secondsToX(
      placement?.audioEnd ?? segment.effectiveAudioEnd,
      size.width,
    );
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

  void _drawFadeOverlay(
    Canvas canvas,
    Size size,
    HighlightSegment segment,
    _TimelinePlacement? placement,
  ) {
    final speed = placement?.speed ?? 1.0;
    final displayStart = placement?.sequenceStart ?? segment.start;
    final displayEnd = placement?.sequenceEnd ?? segment.end;
    final left = _secondsToX(displayStart, size.width);
    final right = _secondsToX(displayEnd, size.width);
    final clipWidth = math.max(2.0, right - left);
    final fadePaint = Paint()
      ..color = colorScheme.surface.withValues(alpha: 0.38);
    final clipTop = layout.videoTop + 2;
    final clipBottom = layout.videoTop + layout.laneHeight - 2;

    if (segment.videoFadeIn > 0) {
      final fadeEnd = _secondsToX(
        displayStart + segment.videoFadeIn / speed,
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
        displayEnd - segment.videoFadeOut / speed,
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

  void _drawTransitionOverlay(
    Canvas canvas,
    Size size,
    _TimelinePlacement placement,
  ) {
    final overlap = placement.transitionOverlap;
    if (overlap <= 0) {
      return;
    }
    final left = _secondsToX(placement.sequenceStart, size.width);
    final right = _secondsToX(placement.sequenceStart + overlap, size.width);
    if (right - left < 1) {
      return;
    }
    final transitionColor = placement.segment.transitionType == 'dip_black'
        ? colorScheme.onSurface
        : colorScheme.primary;
    final fill = Paint()
      ..color = transitionColor.withValues(alpha: 0.22)
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = transitionColor.withValues(alpha: 0.9)
      ..strokeWidth = 1;
    final videoRect = Rect.fromLTRB(
      left,
      layout.videoTop + 2,
      right,
      layout.videoTop + layout.laneHeight - 2,
    );
    canvas.drawRect(videoRect, fill);
    canvas.drawLine(videoRect.topLeft, videoRect.bottomRight, stroke);
    canvas.drawLine(videoRect.bottomLeft, videoRect.topRight, stroke);

    for (final top in [layout.audio1Top, layout.audio2Top]) {
      final audioRect = Rect.fromLTRB(
        left,
        top + 2,
        right,
        top + layout.laneHeight - 2,
      );
      canvas.drawRect(audioRect, fill);
      canvas.drawLine(audioRect.topLeft, audioRect.bottomRight, stroke);
      canvas.drawLine(audioRect.bottomLeft, audioRect.topRight, stroke);
    }

    if (videoRect.width < 42) {
      return;
    }
    final label = placement.segment.transitionType == 'dip_black'
        ? 'Dip ${overlap.toStringAsFixed(1)}s'
        : 'Dissolve ${overlap.toStringAsFixed(1)}s';
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 8,
          fontWeight: FontWeight.w800,
        ),
      ),
      maxLines: 1,
      ellipsis: '…',
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: videoRect.width - 6);
    painter.paint(
      canvas,
      Offset(
        videoRect.center.dx - painter.width / 2,
        videoRect.center.dy - painter.height / 2,
      ),
    );
  }

  void _drawMarkers(Canvas canvas, Size size) {
    for (final marker in timelineMarkers) {
      _drawTimelineMarker(canvas, size, marker);
    }
    final inPoint = markIn == null ? null : _displaySecondsForSource(markIn!);
    final outPoint = markOut == null
        ? null
        : _displaySecondsForSource(markOut!);
    if (inPoint != null) {
      _drawMarker(canvas, size, inPoint, 'IN', colorScheme.primary);
    }
    if (outPoint != null) {
      _drawMarker(canvas, size, outPoint, 'OUT', colorScheme.error);
    }
  }

  void _drawTimelineMarker(Canvas canvas, Size size, TimelineMarker marker) {
    final displaySeconds = _displaySecondsForSource(marker.seconds);
    if (displaySeconds == null) {
      return;
    }
    final x = _secondsToX(displaySeconds, size.width);
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

  double? _displaySecondsForSource(double sourceSeconds) {
    if (!sequenceMode) {
      return sourceSeconds;
    }
    final timelinePlacements = placements;
    final preferred = timelinePlacements.where(
      (placement) => placement.segment.order == selectedSegmentOrder,
    );
    for (final placement in [...preferred, ...timelinePlacements]) {
      if (sourceSeconds >= placement.segment.start &&
          sourceSeconds <= placement.segment.end) {
        return placement.sequenceStart +
            (sourceSeconds - placement.segment.start) / placement.speed;
      }
    }
    return null;
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
        timelineThumbnails != oldDelegate.timelineThumbnails ||
        activeIndex != oldDelegate.activeIndex ||
        activeEdge != oldDelegate.activeEdge ||
        activeTrack != oldDelegate.activeTrack ||
        videoTrackLocked != oldDelegate.videoTrackLocked ||
        audioTrack1Locked != oldDelegate.audioTrack1Locked ||
        audioTrack2Locked != oldDelegate.audioTrack2Locked ||
        sequenceMode != oldDelegate.sequenceMode ||
        sourceDuration != oldDelegate.sourceDuration ||
        colorScheme != oldDelegate.colorScheme;
  }
}
