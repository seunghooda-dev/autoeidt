import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/highlight_segment.dart';
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
    final avDriftFrames = controller.audioVideoLengthDriftFrames(selected);
    final hasAvDrift = controller.segmentHasAudioLengthDrift(selected);
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
                  ? '${selected.topicId > 0 ? 'T${selected.topicId} · ' : ''}${selected.source} · ${selected.score.toStringAsFixed(1)}'
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
        _TimecodeRow(
          label: 'A2',
          start: formatSeconds(selected.effectiveAudioStart),
          end: formatSeconds(selected.effectiveAudioEnd),
        ),
        if (hasAvDrift) ...[
          const SizedBox(height: 8),
          _SyncWarning(
            driftFrames: avDriftFrames,
            onPressed: controller.anyAudioTrackEditLocked
                ? null
                : editor.syncSelectedAudioToVideoLength,
          ),
        ],
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
          onChanged:
              controller.videoTrackLocked || controller.anyAudioTrackEditLocked
              ? null
              : editor.setSelectedPlaybackSpeed,
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: controller.canRateStretchSelectedToMarks
                ? editor.rateStretchSelectedToMarks
                : null,
            icon: const Icon(Icons.speed, size: 18),
            label: const Text('Fit In/Out'),
          ),
        ),
        const SizedBox(height: 8),
        _TransitionControl(
          type: selected.transitionType,
          duration: selected.transitionDuration,
          maxDuration: controller.selectedTransitionMaxDuration,
          enabled: controller.canApplySelectedTransition,
          firstClip: selected.order == 1,
          onTypeChanged: controller.canApplySelectedTransition
              ? editor.setSelectedTransitionType
              : null,
          onDurationChanged:
              controller.canApplySelectedTransition &&
                  selected.transitionType != 'cut'
              ? editor.setSelectedTransitionDuration
              : null,
        ),
        const SizedBox(height: 14),
        _InspectorSectionHeader(
          icon: Icons.open_with,
          label: 'Motion / Opacity',
          resetTooltip: '모션 및 불투명도 초기화',
          onReset: controller.videoTrackLocked
              ? null
              : editor.resetSelectedMotion,
        ),
        const SizedBox(height: 6),
        _PropertySlider(
          key: const Key('clip-video-opacity'),
          icon: Icons.opacity,
          label: 'Opacity',
          value: selected.videoOpacity.clamp(0.0, 1.0).toDouble(),
          min: 0,
          max: 1,
          divisions: 100,
          valueLabel: '${(selected.videoOpacity * 100).round()}%',
          onChanged: controller.videoTrackLocked
              ? null
              : editor.setSelectedVideoOpacity,
        ),
        const SizedBox(height: 8),
        _PropertySlider(
          key: const Key('clip-video-scale'),
          icon: Icons.zoom_out_map,
          label: 'Scale',
          value: selected.videoScale.clamp(1.0, 3.0).toDouble(),
          min: 1,
          max: 3,
          divisions: 200,
          valueLabel: '${(selected.videoScale * 100).round()}%',
          onChanged: controller.videoTrackLocked
              ? null
              : editor.setSelectedVideoScale,
        ),
        const SizedBox(height: 8),
        _PropertySlider(
          key: const Key('clip-video-position-x'),
          icon: Icons.swap_horiz,
          label: 'Position X',
          value: selected.videoPositionX.clamp(-1.0, 1.0).toDouble(),
          min: -1,
          max: 1,
          divisions: 200,
          valueLabel: '${(selected.videoPositionX * 100).round()}',
          onChanged: controller.videoTrackLocked
              ? null
              : editor.setSelectedVideoPositionX,
        ),
        const SizedBox(height: 8),
        _PropertySlider(
          key: const Key('clip-video-position-y'),
          icon: Icons.swap_vert,
          label: 'Position Y',
          value: selected.videoPositionY.clamp(-1.0, 1.0).toDouble(),
          min: -1,
          max: 1,
          divisions: 200,
          valueLabel: '${(selected.videoPositionY * 100).round()}',
          onChanged: controller.videoTrackLocked
              ? null
              : editor.setSelectedVideoPositionY,
        ),
        const SizedBox(height: 8),
        _PropertySlider(
          key: const Key('clip-video-rotation'),
          icon: Icons.rotate_right,
          label: 'Rotation',
          value: selected.videoRotation.clamp(-180.0, 180.0).toDouble(),
          min: -180,
          max: 180,
          divisions: 360,
          valueLabel: '${selected.videoRotation.round()}°',
          onChanged: controller.videoTrackLocked
              ? null
              : editor.setSelectedVideoRotation,
        ),
        const SizedBox(height: 8),
        _FocusStatus(
          confidence: selected.focusConfidence,
          onReset: controller.videoTrackLocked
              ? null
              : editor.resetSelectedFocus,
        ),
        const SizedBox(height: 8),
        _AudioRoutingPanel(
          channelCount: controller.sourceAudioChannelCount,
          leftChannel: selected.audioSourceChannelLeft,
          rightChannel: selected.audioSourceChannelRight,
          onLeftChanged: controller.anyAudioTrackEditLocked
              ? null
              : editor.setSelectedAudioSourceChannelLeft,
          onRightChanged: controller.anyAudioTrackEditLocked
              ? null
              : editor.setSelectedAudioSourceChannelRight,
        ),
        const SizedBox(height: 8),
        _LoudnessTargetControl(
          enabled: selected.audioNormalize,
          target: selected.audioLoudnessTarget,
          onChanged: controller.anyAudioTrackEditLocked
              ? null
              : editor.setSelectedAudioLoudnessTarget,
        ),
        const SizedBox(height: 8),
        _PropertySlider(
          icon: Icons.align_horizontal_center,
          label: 'Reframe X',
          value: selected.focusX.clamp(0.0, 1.0).toDouble(),
          min: 0,
          max: 1,
          divisions: 100,
          valueLabel: '${(selected.focusX * 100).round()}%',
          onChanged: controller.videoTrackLocked
              ? null
              : editor.setSelectedFocusX,
        ),
        const SizedBox(height: 8),
        _PropertySlider(
          icon: Icons.align_vertical_center,
          label: 'Reframe Y',
          value: selected.focusY.clamp(0.0, 1.0).toDouble(),
          min: 0,
          max: 1,
          divisions: 100,
          valueLabel: '${(selected.focusY * 100).round()}%',
          onChanged: controller.videoTrackLocked
              ? null
              : editor.setSelectedFocusY,
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
              onSelected: controller.anyAudioTrackEditLocked
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
              onSelected: controller.anyAudioTrackEditLocked
                  ? null
                  : (_) => editor.toggleSelectedAudioMute(),
              avatar: Icon(
                selected.audioMuted
                    ? Icons.volume_off_outlined
                    : Icons.volume_up_outlined,
                size: 18,
              ),
              label: Text(selected.audioMuted ? '음소거 해제' : 'A1/A2 음소거'),
            ),
            FilterChip(
              selected: selected.audioChannel1Enabled,
              onSelected: controller.audioTrack1EditLocked
                  ? null
                  : (_) => editor.toggleSelectedAudioChannel1(),
              avatar: Icon(
                selected.audioChannel1Enabled
                    ? Icons.check_box_outlined
                    : Icons.check_box_outline_blank,
                size: 18,
              ),
              label: Text(selected.audioChannel1Enabled ? 'A1 활성' : 'A1 꺼짐'),
            ),
            FilterChip(
              selected: selected.audioChannel2Enabled,
              onSelected: controller.audioTrack2EditLocked
                  ? null
                  : (_) => editor.toggleSelectedAudioChannel2(),
              avatar: Icon(
                selected.audioChannel2Enabled
                    ? Icons.check_box_outlined
                    : Icons.check_box_outline_blank,
                size: 18,
              ),
              label: Text(selected.audioChannel2Enabled ? 'A2 활성' : 'A2 꺼짐'),
            ),
            FilterChip(
              selected: selected.audioNormalize,
              onSelected: controller.anyAudioTrackEditLocked
                  ? null
                  : (_) => editor.toggleSelectedAudioNormalize(),
              avatar: const Icon(Icons.auto_graph, size: 18),
              label: const Text('Loudness'),
            ),
            IconButton.outlined(
              tooltip: 'A1/A2 1프레임 앞으로',
              onPressed:
                  selected.audioLinked || controller.anyAudioTrackEditLocked
                  ? null
                  : () => editor.nudgeSelectedAudioFrames(-1),
              icon: const Icon(Icons.keyboard_double_arrow_left),
            ),
            IconButton.outlined(
              tooltip: 'A1/A2 1프레임 뒤로',
              onPressed:
                  selected.audioLinked || controller.anyAudioTrackEditLocked
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
          onChanged: controller.anyAudioTrackEditLocked
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
          onChanged: controller.anyAudioTrackEditLocked
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
          onChanged: controller.anyAudioTrackEditLocked
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
          onChanged: controller.anyAudioTrackEditLocked
              ? null
              : editor.setSelectedAudioFadeOut,
        ),
      ],
    );
  }
}

class _InspectorSectionHeader extends StatelessWidget {
  const _InspectorSectionHeader({
    required this.icon,
    required this.label,
    required this.resetTooltip,
    required this.onReset,
  });

  final IconData icon;
  final String label;
  final String resetTooltip;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 17, color: colorScheme.primary),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        IconButton(
          key: const Key('clip-motion-reset'),
          tooltip: resetTooltip,
          visualDensity: VisualDensity.compact,
          onPressed: onReset,
          icon: const Icon(Icons.restart_alt, size: 18),
        ),
      ],
    );
  }
}

class _TransitionControl extends StatelessWidget {
  const _TransitionControl({
    required this.type,
    required this.duration,
    required this.maxDuration,
    required this.enabled,
    required this.firstClip,
    required this.onTypeChanged,
    required this.onDurationChanged,
  });

  final String type;
  final double duration;
  final double maxDuration;
  final bool enabled;
  final bool firstClip;
  final ValueChanged<String>? onTypeChanged;
  final ValueChanged<double>? onDurationChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final safeType = supportedClipTransitionTypes.contains(type) ? type : 'cut';
    final active = safeType != 'cut';
    final sliderMax = maxDuration.clamp(0.1, 3.0).toDouble();
    final sliderDivisions = ((sliderMax - 0.1) * 10)
        .round()
        .clamp(1, 29)
        .toInt();
    return Container(
      key: const Key('clip-transition-control'),
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 6),
      decoration: BoxDecoration(
        color: active
            ? colorScheme.primaryContainer.withValues(alpha: 0.25)
            : colorScheme.surfaceContainerHighest,
        border: Border.all(
          color: active
              ? colorScheme.primary.withValues(alpha: 0.65)
              : colorScheme.outline,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                active ? Icons.compare : Icons.vertical_align_center,
                size: 17,
                color: active
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Transition In',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              if (active)
                Text(
                  '${duration.toStringAsFixed(1)}s',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 5),
          DropdownButton<String>(
            key: const Key('clip-transition-type'),
            isExpanded: true,
            value: safeType,
            onChanged: onTypeChanged == null
                ? null
                : (value) {
                    if (value != null) {
                      onTypeChanged!(value);
                    }
                  },
            items: const [
              DropdownMenuItem(value: 'cut', child: Text('Cut')),
              DropdownMenuItem(
                value: 'cross_dissolve',
                child: Text('Cross Dissolve'),
              ),
              DropdownMenuItem(value: 'dip_black', child: Text('Dip to Black')),
            ],
          ),
          if (active) ...[
            Slider(
              key: const Key('clip-transition-duration'),
              value: duration.clamp(0.1, sliderMax).toDouble(),
              min: 0.1,
              max: sliderMax,
              divisions: sliderDivisions,
              label: '${duration.toStringAsFixed(1)}s',
              onChanged: onDurationChanged,
            ),
          ] else
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                firstClip ? 'Sequence start' : 'Hard cut',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}

class _AudioRoutingPanel extends StatelessWidget {
  const _AudioRoutingPanel({
    required this.channelCount,
    required this.leftChannel,
    required this.rightChannel,
    required this.onLeftChanged,
    required this.onRightChanged,
  });

  final int channelCount;
  final int leftChannel;
  final int rightChannel;
  final ValueChanged<int>? onLeftChanged;
  final ValueChanged<int>? onRightChanged;

  @override
  Widget build(BuildContext context) {
    final safeCount = channelCount.clamp(1, 64).toInt();
    final items = [
      for (var channel = 1; channel <= safeCount; channel++)
        DropdownMenuItem<int>(
          value: channel,
          child: Text('Source CH $channel'),
        ),
    ];
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.cable, size: 17),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Source channel routing',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              const SizedBox(width: 8),
              Text('$safeCount ch'),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _ChannelRouteDropdown(
                  label: 'A1 / Left',
                  value: leftChannel.clamp(1, safeCount).toInt(),
                  items: items,
                  onChanged: onLeftChanged,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ChannelRouteDropdown(
                  label: 'A2 / Right',
                  value: rightChannel.clamp(1, safeCount).toInt(),
                  items: items,
                  onChanged: onRightChanged,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            'Proxy preview uses a safety mix. This routing is applied to the final render.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _ChannelRouteDropdown extends StatelessWidget {
  const _ChannelRouteDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final int value;
  final List<DropdownMenuItem<int>> items;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        DropdownButton<int>(
          isExpanded: true,
          value: value,
          items: items,
          onChanged: onChanged == null
              ? null
              : (next) {
                  if (next != null) {
                    onChanged!(next);
                  }
                },
        ),
      ],
    );
  }
}

class _LoudnessTargetControl extends StatelessWidget {
  const _LoudnessTargetControl({
    required this.enabled,
    required this.target,
    required this.onChanged,
  });

  final bool enabled;
  final double target;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    const targets = [-14.0, -16.0, -24.0];
    final selectedTarget = targets.reduce(
      (current, candidate) =>
          (candidate - target).abs() < (current - target).abs()
          ? candidate
          : current,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(
            enabled ? Icons.graphic_eq : Icons.graphic_eq_outlined,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Loudness target'),
                Text(
                  enabled ? 'Normalization enabled' : 'Normalization off',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          DropdownButton<double>(
            value: selectedTarget,
            onChanged: onChanged == null
                ? null
                : (value) {
                    if (value != null) {
                      onChanged!(value);
                    }
                  },
            items: const [
              DropdownMenuItem(value: -14, child: Text('YouTube  -14 LUFS')),
              DropdownMenuItem(value: -16, child: Text('Voice  -16 LUFS')),
              DropdownMenuItem(value: -24, child: Text('Broadcast  -24 LKFS')),
            ],
          ),
        ],
      ),
    );
  }
}

class _FocusStatus extends StatelessWidget {
  const _FocusStatus({required this.confidence, required this.onReset});

  final double confidence;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tracked = confidence > 0.01;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        border: Border.all(color: colorScheme.outline),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Icon(
            tracked ? Icons.face_retouching_natural : Icons.center_focus_strong,
            size: 17,
            color: tracked ? colorScheme.primary : colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              tracked
                  ? 'Speaker track ${(confidence * 100).round()}%'
                  : 'Manual / center framing',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          IconButton(
            tooltip: '구도 중앙 초기화',
            onPressed: onReset,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.center_focus_strong, size: 17),
          ),
        ],
      ),
    );
  }
}

class _SyncWarning extends StatelessWidget {
  const _SyncWarning({required this.driftFrames, required this.onPressed});

  final int driftFrames;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.tertiaryContainer.withValues(alpha: 0.55),
        border: Border.all(color: colorScheme.tertiary.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(
            Icons.sync_problem,
            size: 18,
            color: colorScheme.onTertiaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'A/V length drift ${driftFrames}f',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: colorScheme.onTertiaryContainer,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: onPressed,
            icon: const Icon(Icons.sync, size: 16),
            label: const Text('Sync'),
          ),
        ],
      ),
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
    super.key,
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
