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
    final canUseMarks = controller.hasValidMarks;

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
              label: '현재',
              value: formatSeconds(controller.currentPositionSeconds),
            ),
            _MetricChip(
              icon: Icons.keyboard_tab,
              label: 'In',
              value: controller.markIn == null
                  ? '--:--'
                  : formatSeconds(controller.markIn!),
            ),
            _MetricChip(
              icon: Icons.keyboard_return,
              label: 'Out',
              value: controller.markOut == null
                  ? '--:--'
                  : formatSeconds(controller.markOut!),
            ),
            _MetricChip(
              icon: Icons.content_cut,
              label: 'Out',
              value: formatSeconds(controller.outputDurationSeconds),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconButton.outlined(
              tooltip: '되돌리기',
              onPressed: controller.canUndo
                  ? context.read<EditorController>().undo
                  : null,
              icon: const Icon(Icons.undo),
            ),
            IconButton.outlined(
              tooltip: '다시 실행',
              onPressed: controller.canRedo
                  ? context.read<EditorController>().redo
                  : null,
              icon: const Icon(Icons.redo),
            ),
            OutlinedButton.icon(
              onPressed: controller.hasTimeline
                  ? context.read<EditorController>().setMarkInFromPlayhead
                  : null,
              icon: const Icon(Icons.start),
              label: const Text('In'),
            ),
            OutlinedButton.icon(
              onPressed: controller.hasTimeline
                  ? context.read<EditorController>().setMarkOutFromPlayhead
                  : null,
              icon: const Icon(Icons.flag_outlined),
              label: const Text('Out'),
            ),
            FilledButton.tonalIcon(
              onPressed: canUseMarks
                  ? context.read<EditorController>().addMarkedSegment
                  : null,
              icon: const Icon(Icons.add_box_outlined),
              label: const Text('Add'),
            ),
            OutlinedButton.icon(
              onPressed: selected != null && canUseMarks
                  ? context.read<EditorController>().applyMarksToSelectedSegment
                  : null,
              icon: const Icon(Icons.swap_horiz),
              label: const Text('Apply'),
            ),
            _ContextHint(),
            IconButton.outlined(
              tooltip: '타임라인 축소',
              onPressed: controller.hasTimeline
                  ? () => context.read<EditorController>().zoomTimeline(-0.5)
                  : null,
              icon: const Icon(Icons.zoom_out),
            ),
            IconButton.outlined(
              tooltip: '타임라인 확대',
              onPressed: controller.hasTimeline
                  ? () => context.read<EditorController>().zoomTimeline(0.5)
                  : null,
              icon: const Icon(Icons.zoom_in),
            ),
          ],
        ),
      ],
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
              'Right click: Split · Delete · Audio',
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
