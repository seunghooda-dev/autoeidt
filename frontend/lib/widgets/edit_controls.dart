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
    final outputSeconds = controller.segments.fold<double>(
      0,
      (total, segment) => total + segment.duration,
    );
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
              label: 'Export',
              value: formatSeconds(outputSeconds),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: controller.hasTimeline
                  ? context.read<EditorController>().setMarkInFromPlayhead
                  : null,
              icon: const Icon(Icons.start),
              label: const Text('In 지정'),
            ),
            OutlinedButton.icon(
              onPressed: controller.hasTimeline
                  ? context.read<EditorController>().setMarkOutFromPlayhead
                  : null,
              icon: const Icon(Icons.flag_outlined),
              label: const Text('Out 지정'),
            ),
            FilledButton.tonalIcon(
              onPressed: canUseMarks
                  ? context.read<EditorController>().addMarkedSegment
                  : null,
              icon: const Icon(Icons.add_box_outlined),
              label: const Text('클립 추가'),
            ),
            OutlinedButton.icon(
              onPressed: selected != null && canUseMarks
                  ? context.read<EditorController>().applyMarksToSelectedSegment
                  : null,
              icon: const Icon(Icons.swap_horiz),
              label: const Text('선택 클립에 적용'),
            ),
            OutlinedButton.icon(
              onPressed: controller.markIn != null || controller.markOut != null
                  ? context.read<EditorController>().clearMarks
                  : null,
              icon: const Icon(Icons.clear),
              label: const Text('마크 지우기'),
            ),
            OutlinedButton.icon(
              onPressed: selected == null
                  ? null
                  : context.read<EditorController>().deleteSelectedSegment,
              icon: const Icon(Icons.delete_outline),
              label: const Text('선택 클립 삭제'),
            ),
          ],
        ),
        if (selected != null) ...[
          const SizedBox(height: 10),
          Text(
            '선택 클립 ${selected.order}: ${formatSeconds(selected.start)} - ${formatSeconds(selected.end)}',
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ],
      ],
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
