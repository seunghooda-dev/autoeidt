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
      (total, segment) => total + segment.outputDuration,
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
            _MetricChip(
              icon: Icons.zoom_in,
              label: 'Zoom',
              value: '${controller.timelineZoom.toStringAsFixed(1)}x',
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
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
            OutlinedButton.icon(
              onPressed: selected == null
                  ? null
                  : context.read<EditorController>().duplicateSelectedSegment,
              icon: const Icon(Icons.content_copy),
              label: const Text('복제'),
            ),
            OutlinedButton.icon(
              onPressed: selected == null
                  ? null
                  : context.read<EditorController>().splitSelectedAtPlayhead,
              icon: const Icon(Icons.call_split),
              label: const Text('Split'),
            ),
            IconButton.outlined(
              tooltip: '선택 클립 앞으로',
              onPressed: selected == null
                  ? null
                  : () => context.read<EditorController>().moveSelectedSegment(
                      -1,
                    ),
              icon: const Icon(Icons.keyboard_arrow_up),
            ),
            IconButton.outlined(
              tooltip: '선택 클립 뒤로',
              onPressed: selected == null
                  ? null
                  : () =>
                        context.read<EditorController>().moveSelectedSegment(1),
              icon: const Icon(Icons.keyboard_arrow_down),
            ),
            IconButton.outlined(
              tooltip: '타임라인 확대',
              onPressed: controller.hasTimeline
                  ? () => context.read<EditorController>().zoomTimeline(0.5)
                  : null,
              icon: const Icon(Icons.zoom_in),
            ),
            IconButton.outlined(
              tooltip: '타임라인 축소',
              onPressed: controller.hasTimeline
                  ? () => context.read<EditorController>().zoomTimeline(-0.5)
                  : null,
              icon: const Icon(Icons.zoom_out),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: '16:9', label: Text('16:9')),
                ButtonSegment(value: '9:16', label: Text('9:16')),
              ],
              selected: {controller.exportAspectRatio},
              onSelectionChanged: controller.hasTimeline
                  ? (value) => context
                        .read<EditorController>()
                        .setExportAspectRatio(value.first)
                  : null,
            ),
            FilterChip(
              selected: controller.includeCaptions,
              onSelected: controller.hasTimeline
                  ? context.read<EditorController>().setIncludeCaptions
                  : null,
              avatar: const Icon(Icons.closed_caption_outlined, size: 18),
              label: const Text('자막 포함'),
            ),
            OutlinedButton.icon(
              onPressed: controller.hasTimeline
                  ? () =>
                        context.read<EditorController>().saveProjectToBackend()
                  : null,
              icon: const Icon(Icons.save_outlined),
              label: const Text('프로젝트 저장'),
            ),
            OutlinedButton.icon(
              onPressed: controller.hasTimeline
                  ? context.read<EditorController>().exportProjectFile
                  : null,
              icon: const Icon(Icons.file_download_outlined),
              label: const Text('내보내기'),
            ),
            OutlinedButton.icon(
              onPressed: context.read<EditorController>().importProjectFile,
              icon: const Icon(Icons.folder_open),
              label: const Text('불러오기'),
            ),
          ],
        ),
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
