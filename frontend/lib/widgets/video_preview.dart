import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/highlight_segment.dart';
import 'time_format.dart';

class VideoPreview extends StatelessWidget {
  const VideoPreview({
    super.key,
    required this.controller,
    required this.volume,
    required this.muted,
    this.onToggleMute,
    this.loading = false,
    this.playWhenReady = false,
    this.onTogglePlayback,
    this.targetAspectRatio,
    this.focusX = 0.5,
    this.focusY = 0.42,
    this.focusKeyframes = const [],
    this.segmentStart = 0,
  });

  final VideoPlayerController? controller;
  final double volume;
  final bool muted;
  final VoidCallback? onToggleMute;
  final bool loading;
  final bool playWhenReady;
  final VoidCallback? onTogglePlayback;
  final double? targetAspectRatio;
  final double focusX;
  final double focusY;
  final List<ReframeKeyframe> focusKeyframes;
  final double segmentStart;

  @override
  Widget build(BuildContext context) {
    final player = controller;
    if (player == null || !player.value.isInitialized) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(2),
          ),
          child: _PreviewPlaceholder(
            loading: loading,
            playWhenReady: playWhenReady,
            onTogglePlayback: onTogglePlayback,
          ),
        ),
      );
    }

    final sourceAspectRatio = player.value.aspectRatio == 0
        ? 16 / 9
        : player.value.aspectRatio;
    final outputAspectRatio = targetAspectRatio ?? sourceAspectRatio;
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: AspectRatio(
        aspectRatio: outputAspectRatio,
        child: ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: player,
          builder: (context, value, _) {
            final positionSeconds = value.position.inMilliseconds / 1000;
            final trackedFocus = _reframeFocusAt(
              focusKeyframes,
              positionSeconds - segmentStart,
              fallbackX: focusX,
              fallbackY: focusY,
            );
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (onTogglePlayback != null) {
                  onTogglePlayback!();
                } else {
                  value.isPlaying ? player.pause() : player.play();
                }
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _ReframedVideo(
                    controller: player,
                    cropToFill: outputAspectRatio < 1,
                    focusX: trackedFocus.$1,
                    focusY: trackedFocus.$2,
                  ),
                  if (!value.isPlaying)
                    _PausedOverlay(
                      controller: player,
                      onTogglePlayback: onTogglePlayback,
                    ),
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: _VideoControls(
                      controller: player,
                      volume: volume,
                      muted: muted,
                      onToggleMute: onToggleMute,
                      onTogglePlayback: onTogglePlayback,
                      compact: outputAspectRatio < 1,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PreviewPlaceholder extends StatelessWidget {
  const _PreviewPlaceholder({
    required this.loading,
    required this.playWhenReady,
    required this.onTogglePlayback,
  });

  final bool loading;
  final bool playWhenReady;
  final VoidCallback? onTogglePlayback;

  @override
  Widget build(BuildContext context) {
    final mutedColor = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading)
            const SizedBox.square(
              dimension: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            )
          else
            Icon(Icons.movie_outlined, color: mutedColor, size: 40),
          const SizedBox(height: 12),
          Text(
            loading ? (playWhenReady ? '준비되면 자동 재생' : '빠른 프리뷰 준비 중') : '프리뷰 준비',
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: mutedColor),
          ),
          const SizedBox(height: 8),
          IconButton.filledTonal(
            key: const Key('preview-play-when-ready'),
            tooltip: playWhenReady ? '자동 재생 취소' : '재생',
            onPressed: onTogglePlayback,
            icon: Icon(playWhenReady ? Icons.pause : Icons.play_arrow),
          ),
        ],
      ),
    );
  }
}

(double, double) _reframeFocusAt(
  List<ReframeKeyframe> keyframes,
  double seconds, {
  required double fallbackX,
  required double fallbackY,
}) {
  if (keyframes.isEmpty) {
    return (fallbackX, fallbackY);
  }
  final ordered = [...keyframes]..sort((a, b) => a.time.compareTo(b.time));
  if (seconds <= ordered.first.time) {
    return (ordered.first.x, ordered.first.y);
  }
  for (var index = 0; index < ordered.length - 1; index++) {
    final left = ordered[index];
    final right = ordered[index + 1];
    if (seconds > right.time) {
      continue;
    }
    final midpoint = (left.time + right.time) / 2;
    final transitionHalf = math.min(
      0.12,
      math.max(0.03, (right.time - left.time) / 6),
    );
    final transitionStart = math.max(left.time, midpoint - transitionHalf);
    final transitionEnd = math.min(right.time, midpoint + transitionHalf);
    if (seconds <= transitionStart) {
      return (left.x, left.y);
    }
    if (seconds >= transitionEnd) {
      return (right.x, right.y);
    }
    final ratio =
        ((seconds - transitionStart) /
                math.max(0.001, transitionEnd - transitionStart))
            .clamp(0.0, 1.0)
            .toDouble();
    return (
      left.x + (right.x - left.x) * ratio,
      left.y + (right.y - left.y) * ratio,
    );
  }
  return (ordered.last.x, ordered.last.y);
}

class _ReframedVideo extends StatelessWidget {
  const _ReframedVideo({
    required this.controller,
    required this.cropToFill,
    required this.focusX,
    required this.focusY,
  });

  final VideoPlayerController controller;
  final bool cropToFill;
  final double focusX;
  final double focusY;

  @override
  Widget build(BuildContext context) {
    final size = controller.value.size;
    if (size.width <= 0 || size.height <= 0) {
      return VideoPlayer(controller);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        var alignment = Alignment.center;
        if (cropToFill &&
            constraints.maxWidth.isFinite &&
            constraints.maxHeight.isFinite) {
          final scale = math.max(
            constraints.maxWidth / size.width,
            constraints.maxHeight / size.height,
          );
          final scaledWidth = size.width * scale;
          final scaledHeight = size.height * scale;
          final overflowX = math.max(0.0, scaledWidth - constraints.maxWidth);
          final overflowY = math.max(0.0, scaledHeight - constraints.maxHeight);
          final cropX =
              (focusX.clamp(0.0, 1.0) * scaledWidth - constraints.maxWidth / 2)
                  .clamp(0.0, overflowX)
                  .toDouble();
          final cropY =
              (focusY.clamp(0.0, 1.0) * scaledHeight -
                      constraints.maxHeight * 0.38)
                  .clamp(0.0, overflowY)
                  .toDouble();
          alignment = Alignment(
            overflowX <= 0 ? 0 : cropX / overflowX * 2 - 1,
            overflowY <= 0 ? 0 : cropY / overflowY * 2 - 1,
          );
        }
        return ClipRect(
          child: FittedBox(
            fit: cropToFill ? BoxFit.cover : BoxFit.contain,
            alignment: alignment,
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: VideoPlayer(controller),
            ),
          ),
        );
      },
    );
  }
}

class _PausedOverlay extends StatelessWidget {
  const _PausedOverlay({
    required this.controller,
    required this.onTogglePlayback,
  });

  final VideoPlayerController controller;
  final VoidCallback? onTogglePlayback;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.18)),
      child: Center(
        child: Tooltip(
          message: '재생 / 일시정지 (Space)',
          child: FilledButton.tonalIcon(
            onPressed: onTogglePlayback ?? controller.play,
            icon: const Icon(Icons.play_arrow, size: 30),
            label: const Text('Play'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.black.withValues(alpha: 0.72),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoControls extends StatelessWidget {
  const _VideoControls({
    required this.controller,
    required this.volume,
    required this.muted,
    required this.onToggleMute,
    required this.onTogglePlayback,
    required this.compact,
  });

  final VideoPlayerController controller;
  final double volume;
  final bool muted;
  final VoidCallback? onToggleMute;
  final VoidCallback? onTogglePlayback;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final durationSeconds = value.duration.inMilliseconds / 1000;
        final positionSeconds = value.position.inMilliseconds / 1000;
        final sliderValue = durationSeconds <= 0
            ? 0.0
            : positionSeconds.clamp(0.0, durationSeconds).toDouble();

        return DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Row(
              children: [
                IconButton(
                  tooltip: value.isPlaying ? '일시정지' : '재생',
                  color: Colors.white,
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    if (onTogglePlayback != null) {
                      onTogglePlayback!();
                    } else {
                      value.isPlaying ? controller.pause() : controller.play();
                    }
                  },
                  icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
                ),
                Expanded(
                  child: Slider(
                    value: sliderValue,
                    min: 0,
                    max: durationSeconds <= 0 ? 1 : durationSeconds,
                    onChanged: (seconds) {
                      controller.seekTo(
                        Duration(milliseconds: (seconds * 1000).round()),
                      );
                    },
                  ),
                ),
                IconButton(
                  tooltip: '프리뷰 음소거 전환',
                  color: Colors.white,
                  visualDensity: VisualDensity.compact,
                  onPressed: onToggleMute,
                  icon: Icon(
                    muted
                        ? Icons.volume_off_outlined
                        : Icons.volume_up_outlined,
                  ),
                ),
                SizedBox(
                  width: compact ? 94 : 236,
                  child: Text(
                    compact
                        ? formatSeconds(positionSeconds)
                        : '${formatSeconds(positionSeconds)} / ${formatSeconds(durationSeconds)} · ${(muted ? 0 : volume * 100).round()}%',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: Theme.of(
                      context,
                    ).textTheme.labelMedium?.copyWith(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
