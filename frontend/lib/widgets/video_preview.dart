import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'time_format.dart';

class VideoPreview extends StatelessWidget {
  const VideoPreview({super.key, required this.controller});

  final VideoPlayerController? controller;

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
        child: Stack(
          fit: StackFit.expand,
          children: [
            VideoPlayer(player),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: _VideoControls(controller: player),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoControls extends StatelessWidget {
  const _VideoControls({required this.controller});

  final VideoPlayerController controller;

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
                SizedBox(
                  width: 194,
                  child: Text(
                    '${formatSeconds(positionSeconds)} / ${formatSeconds(durationSeconds)}',
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
