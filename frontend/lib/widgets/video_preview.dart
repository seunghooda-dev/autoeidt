import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'time_format.dart';

class VideoPreview extends StatelessWidget {
  const VideoPreview({
    super.key,
    required this.controller,
    required this.volume,
    required this.muted,
    this.onToggleMute,
  });

  final VideoPlayerController? controller;
  final double volume;
  final bool muted;
  final VoidCallback? onToggleMute;

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
          child: Center(
            child: Icon(
              Icons.movie_outlined,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              size: 44,
            ),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: AspectRatio(
        aspectRatio: player.value.aspectRatio == 0
            ? 16 / 9
            : player.value.aspectRatio,
        child: ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: player,
          builder: (context, value, _) {
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                value.isPlaying ? player.pause() : player.play();
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  VideoPlayer(player),
                  if (!value.isPlaying) _PausedOverlay(controller: player),
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: _VideoControls(
                      controller: player,
                      volume: volume,
                      muted: muted,
                      onToggleMute: onToggleMute,
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

class _PausedOverlay extends StatelessWidget {
  const _PausedOverlay({required this.controller});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.18)),
      child: Center(
        child: Tooltip(
          message: '재생 / 일시정지 (Space)',
          child: FilledButton.tonalIcon(
            onPressed: controller.play,
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
  });

  final VideoPlayerController controller;
  final double volume;
  final bool muted;
  final VoidCallback? onToggleMute;

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
                    value.isPlaying ? controller.pause() : controller.play();
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
                  width: 236,
                  child: Text(
                    '${formatSeconds(positionSeconds)} / ${formatSeconds(durationSeconds)} · ${(muted ? 0 : volume * 100).round()}%',
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
