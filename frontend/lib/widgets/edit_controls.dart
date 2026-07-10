import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/editor_controller.dart';
import 'time_format.dart';

class EditControls extends StatelessWidget {
  const EditControls({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<EditorController>();
    final selected = controller.selectedSegment;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _MetricChip(
              icon: Icons.play_arrow,
              label: controller.isProgramMonitor ? 'Program' : 'Source',
              value: formatSeconds(controller.monitorPositionSeconds),
            ),
            _MetricChip(
              icon: Icons.keyboard_tab,
              label: controller.isProgramMonitor ? 'Src In' : 'In',
              value: controller.markIn == null
                  ? '--:--'
                  : formatSeconds(controller.markIn!),
            ),
            _MetricChip(
              icon: Icons.keyboard_return,
              label: controller.isProgramMonitor ? 'Src Out' : 'Out',
              value: controller.markOut == null
                  ? '--:--'
                  : formatSeconds(controller.markOut!),
            ),
            _MetricChip(
              icon: Icons.content_cut,
              label: 'Export',
              value: formatSeconds(controller.outputDurationSeconds),
            ),
            _MetricChip(
              icon: Icons.zoom_in,
              label: 'Zoom',
              value: '${controller.timelineZoom.toStringAsFixed(1)}x',
            ),
            _MetricChip(
              icon: Icons.keyboard_double_arrow_right,
              label: 'Shuttle',
              value: controller.playbackShuttleLabel,
            ),
            _MetricChip(
              icon: controller.isRazorTool
                  ? Icons.content_cut
                  : Icons.near_me_outlined,
              label: 'Tool',
              value: controller.timelineToolLabel,
            ),
            if (selected != null)
              _MetricChip(
                icon: selected.audioLinked ? Icons.link : Icons.link_off,
                label: 'Selected',
                value: 'Clip ${selected.order}',
              ),
            if (selected != null)
              _MetricChip(
                icon: Icons.speed,
                label: 'Speed',
                value: '${selected.playbackSpeed.toStringAsFixed(2)}x',
              ),
            _ContextHint(),
            _TrackLegend(color: const Color(0xFF79C98D), label: 'V1 Video'),
            _TrackLegend(color: const Color(0xFFE7A66A), label: 'A1 Audio'),
            _TrackLegend(color: const Color(0xFFE7A66A), label: 'A2 Audio'),
          ],
        ),
      ],
    );
  }
}

class _TrackLegend extends StatelessWidget {
  const _TrackLegend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _ContextHint extends StatelessWidget {
  const _ContextHint();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        border: Border.all(color: colorScheme.outline),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.mouse_outlined, size: 15, color: colorScheme.primary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              'Right click: Premiere shortcuts',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        border: Border.all(color: colorScheme.outline),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colorScheme.primary),
          const SizedBox(width: 6),
          Text('$label $value', style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }
}
