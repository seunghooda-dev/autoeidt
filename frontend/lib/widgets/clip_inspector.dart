import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/editor_controller.dart';
import 'time_format.dart';

class ClipInspector extends StatelessWidget {
  const ClipInspector({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<EditorController>();
    final selected = controller.selectedSegment;
    if (selected == null) {
      return Center(
        child: Text('선택된 클립 없음', style: Theme.of(context).textTheme.bodyMedium),
      );
    }

    final colorScheme = Theme.of(context).colorScheme;
    final editor = context.read<EditorController>();
    return ListView(
      children: [
        Row(
          children: [
            Icon(Icons.tune, color: colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Clip ${selected.order}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            Text(
              selected.score > 0
                  ? '${selected.source} · ${selected.score.toStringAsFixed(1)}'
                  : selected.source,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _TimecodeRow(
          label: 'V1',
          start: formatSeconds(selected.start),
          end: formatSeconds(selected.end),
        ),
        const SizedBox(height: 8),
        _TimecodeRow(
          label: 'A1',
          start: formatSeconds(selected.effectiveAudioStart),
          end: formatSeconds(selected.effectiveAudioEnd),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilterChip(
              selected: selected.videoEnabled,
              onSelected: controller.videoTrackLocked
                  ? null
                  : (_) => editor.toggleSelectedVideoEnabled(),
              avatar: Icon(
                selected.videoEnabled
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 18,
              ),
              label: Text(selected.videoEnabled ? 'V1 표시' : 'V1 숨김'),
            ),
            IconButton.outlined(
              tooltip: '색 보정 초기화',
              onPressed: controller.videoTrackLocked
                  ? null
                  : editor.resetSelectedColor,
              icon: const Icon(Icons.restart_alt),
            ),
          ],
        ),
        if (selected.tags.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final tag in selected.tags)
                Chip(
                  label: Text(tag),
                  visualDensity: VisualDensity.compact,
                  side: BorderSide(color: colorScheme.outline),
                  backgroundColor: colorScheme.surfaceContainerHighest,
                ),
            ],
          ),
        ],
        const SizedBox(height: 14),
        _PropertySlider(
          icon: Icons.speed,
          label: 'Speed',
          value: selected.playbackSpeed.clamp(0.25, 4.0).toDouble(),
          min: 0.25,
          max: 4,
          divisions: 15,
          valueLabel: '${selected.playbackSpeed.toStringAsFixed(2)}x',
          onChanged: controller.videoTrackLocked || controller.audioTrackLocked
              ? null
              : editor.setSelectedPlaybackSpeed,
        ),
        const SizedBox(height: 8),
        _PropertySlider(
          icon: Icons.gradient_outlined,
          label: 'V Fade In',
          value: selected.videoFadeIn.clamp(0.0, 10.0).toDouble(),
          min: 0,
          max: 10,
          divisions: 20,
          valueLabel: '${selected.videoFadeIn.toStringAsFixed(1)}s',
          onChanged: controller.videoTrackLocked
              ? null
              : editor.setSelectedVideoFadeIn,
        ),
        const SizedBox(height: 8),
        _PropertySlider(
          icon: Icons.gradient,
          label: 'V Fade Out',
          value: selected.videoFadeOut.clamp(0.0, 10.0).toDouble(),
          min: 0,
          max: 10,
          divisions: 20,
          valueLabel: '${selected.videoFadeOut.toStringAsFixed(1)}s',
          onChanged: controller.videoTrackLocked
              ? null
              : editor.setSelectedVideoFadeOut,
        ),
        const SizedBox(height: 8),
        _PropertySlider(
          icon: Icons.brightness_6_outlined,
          label: 'Brightness',
          value: selected.colorBrightness.clamp(-0.3, 0.3).toDouble(),
          min: -0.3,
          max: 0.3,
          divisions: 12,
          valueLabel: selected.colorBrightness.toStringAsFixed(2),
          onChanged: controller.videoTrackLocked
              ? null
              : editor.setSelectedColorBrightness,
        ),
        const SizedBox(height: 8),
        _PropertySlider(
          icon: Icons.contrast,
          label: 'Contrast',
          value: selected.colorContrast.clamp(0.5, 1.8).toDouble(),
          min: 0.5,
          max: 1.8,
          divisions: 13,
          valueLabel: selected.colorContrast.toStringAsFixed(2),
          onChanged: controller.videoTrackLocked
              ? null
              : editor.setSelectedColorContrast,
        ),
        const SizedBox(height: 8),
        _PropertySlider(
          icon: Icons.palette_outlined,
          label: 'Saturation',
          value: selected.colorSaturation.clamp(0.0, 2.0).toDouble(),
          min: 0,
          max: 2,
          divisions: 20,
          valueLabel: selected.colorSaturation.toStringAsFixed(2),
          onChanged: controller.videoTrackLocked
              ? null
              : editor.setSelectedColorSaturation,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilterChip(
              selected: !selected.audioLinked,
              onSelected: controller.audioTrackLocked
                  ? null
                  : (_) {
                      if (selected.audioLinked) {
                        editor.detachAudioForSelectedSegment();
                      } else {
                        editor.relinkAudioForSelectedSegment();
                      }
                    },
              avatar: Icon(
                selected.audioLinked ? Icons.link : Icons.link_off,
                size: 18,
              ),
              label: Text(selected.audioLinked ? '오디오 분리' : '오디오 재연결'),
            ),
            FilterChip(
              selected: selected.audioMuted,
              onSelected: controller.audioTrackLocked
                  ? null
                  : (_) => editor.toggleSelectedAudioMute(),
              avatar: Icon(
                selected.audioMuted
                    ? Icons.volume_off_outlined
                    : Icons.volume_up_outlined,
                size: 18,
              ),
              label: Text(selected.audioMuted ? '음소거 해제' : 'A1 음소거'),
            ),
            FilterChip(
              selected: selected.audioNormalize,
              onSelected: controller.audioTrackLocked
                  ? null
                  : (_) => editor.toggleSelectedAudioNormalize(),
              avatar: const Icon(Icons.auto_graph, size: 18),
              label: const Text('Loudness'),
            ),
            IconButton.outlined(
              tooltip: 'A1 1프레임 앞으로',
              onPressed: selected.audioLinked || controller.audioTrackLocked
                  ? null
                  : () => editor.nudgeSelectedAudioFrames(-1),
              icon: const Icon(Icons.keyboard_double_arrow_left),
            ),
            IconButton.outlined(
              tooltip: 'A1 1프레임 뒤로',
              onPressed: selected.audioLinked || controller.audioTrackLocked
                  ? null
                  : () => editor.nudgeSelectedAudioFrames(1),
              icon: const Icon(Icons.keyboard_double_arrow_right),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _PropertySlider(
          icon: Icons.graphic_eq,
          label: 'Volume',
          value: selected.audioVolume.clamp(0.0, 2.0).toDouble(),
          min: 0,
          max: 2,
          divisions: 20,
          valueLabel: '${(selected.audioVolume * 100).round()}%',
          onChanged: controller.audioTrackLocked
              ? null
              : editor.setSelectedAudioVolume,
        ),
        const SizedBox(height: 8),
        _PropertySlider(
          icon: Icons.balance,
          label: 'Pan',
          value: selected.audioPan.clamp(-1.0, 1.0).toDouble(),
          min: -1,
          max: 1,
          divisions: 20,
          valueLabel: _panLabel(selected.audioPan),
          onChanged: controller.audioTrackLocked
              ? null
              : editor.setSelectedAudioPan,
        ),
        const SizedBox(height: 8),
        _PropertySlider(
          icon: Icons.vertical_align_top,
          label: 'Fade In',
          value: selected.audioFadeIn.clamp(0.0, 10.0).toDouble(),
          min: 0,
          max: 10,
          divisions: 20,
          valueLabel: '${selected.audioFadeIn.toStringAsFixed(1)}s',
          onChanged: controller.audioTrackLocked
              ? null
              : editor.setSelectedAudioFadeIn,
        ),
        const SizedBox(height: 8),
        _PropertySlider(
          icon: Icons.vertical_align_bottom,
          label: 'Fade Out',
          value: selected.audioFadeOut.clamp(0.0, 10.0).toDouble(),
          min: 0,
          max: 10,
          divisions: 20,
          valueLabel: '${selected.audioFadeOut.toStringAsFixed(1)}s',
          onChanged: controller.audioTrackLocked
              ? null
              : editor.setSelectedAudioFadeOut,
        ),
      ],
    );
  }
}

String _panLabel(double value) {
  final clamped = value.clamp(-1.0, 1.0).toDouble();
  if (clamped.abs() < 0.01) {
    return 'C';
  }
  final side = clamped < 0 ? 'L' : 'R';
  return '$side ${(clamped.abs() * 100).round()}';
}

class _TimecodeRow extends StatelessWidget {
  const _TimecodeRow({
    required this.label,
    required this.start,
    required this.end,
  });

  final String label;
  final String start;
  final String end;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        border: Border.all(color: colorScheme.outline),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(label, style: Theme.of(context).textTheme.labelLarge),
          ),
          Expanded(
            child: Text(
              '$start  -  $end',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _PropertySlider extends StatelessWidget {
  const _PropertySlider({
    required this.icon,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.valueLabel,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String valueLabel;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, size: 17, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
            Text(valueLabel, style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          label: valueLabel,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
