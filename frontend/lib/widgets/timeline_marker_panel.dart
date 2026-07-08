import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/job_models.dart';
import '../state/editor_controller.dart';
import 'time_format.dart';

class TimelineMarkerPanel extends StatelessWidget {
  const TimelineMarkerPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<EditorController>();
    final editor = context.read<EditorController>();
    final markers = controller.timelineMarkers;
    final colorScheme = Theme.of(context).colorScheme;

    if (markers.isEmpty) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.bookmarks_outlined,
                color: colorScheme.onSurfaceVariant,
                size: 30,
              ),
              const SizedBox(height: 10),
              Text(
                '마커 없음',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: controller.timelineSourceDuration > 0
                    ? editor.addTimelineMarkerAtPlayhead
                    : null,
                icon: const Icon(Icons.bookmark_add_outlined),
                label: const Text('현재 위치 마커'),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.bookmarks_outlined, color: colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Markers',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            Text(
              '${markers.length}',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            IconButton.outlined(
              tooltip: '이전 마커로 이동',
              onPressed: controller.canJumpToPreviousTimelineMarker
                  ? editor.jumpToPreviousTimelineMarker
                  : null,
              icon: const Icon(Icons.skip_previous),
            ),
            IconButton.outlined(
              tooltip: '다음 마커로 이동',
              onPressed: controller.canJumpToNextTimelineMarker
                  ? editor.jumpToNextTimelineMarker
                  : null,
              icon: const Icon(Icons.skip_next),
            ),
            IconButton.outlined(
              tooltip: '현재 위치에 마커 추가',
              onPressed: controller.timelineSourceDuration > 0
                  ? editor.addTimelineMarkerAtPlayhead
                  : null,
              icon: const Icon(Icons.bookmark_add_outlined),
            ),
            IconButton.outlined(
              tooltip: '모든 마커 삭제',
              onPressed: editor.clearTimelineMarkers,
              icon: const Icon(Icons.bookmark_remove_outlined),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: ListView.separated(
            itemCount: markers.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final marker = markers[index];
              return _MarkerTile(
                marker: marker,
                isActive: _isActiveMarker(
                  controller.currentPositionSeconds,
                  marker,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  bool _isActiveMarker(double playheadSeconds, TimelineMarker marker) {
    return (playheadSeconds - marker.seconds).abs() <=
        timecodeFrameDurationSeconds / 2;
  }
}

class _MarkerTile extends StatelessWidget {
  const _MarkerTile({required this.marker, required this.isActive});

  final TimelineMarker marker;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<EditorController>();
    final colorScheme = Theme.of(context).colorScheme;
    final markerColor = _timelineMarkerColor(colorScheme, marker.color);
    final borderColor = isActive ? markerColor : colorScheme.outline;

    return Material(
      color: isActive
          ? markerColor.withValues(alpha: 0.12)
          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.38),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => controller.seekTo(marker.seconds, autoplay: false),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor.withValues(alpha: 0.78)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Icon(Icons.bookmark, color: markerColor, size: 18),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            marker.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        Text(
                          formatSeconds(marker.seconds),
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                        ),
                      ],
                    ),
                    if (marker.note.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        marker.note,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: '${marker.label} 마커 편집',
                onPressed: () => _showMarkerEditor(context, marker),
                icon: const Icon(Icons.edit_outlined, size: 18),
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                tooltip: '${marker.label} 마커 삭제',
                onPressed: () => controller.deleteTimelineMarker(marker.id),
                icon: const Icon(Icons.close, size: 18),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showMarkerEditor(
    BuildContext context,
    TimelineMarker marker,
  ) async {
    final controller = context.read<EditorController>();
    final result = await showDialog<TimelineMarker>(
      context: context,
      builder: (context) => _MarkerEditDialog(marker: marker),
    );
    if (result == null) {
      return;
    }
    controller.updateTimelineMarker(result);
  }
}

class _MarkerEditDialog extends StatefulWidget {
  const _MarkerEditDialog({required this.marker});

  final TimelineMarker marker;

  @override
  State<_MarkerEditDialog> createState() => _MarkerEditDialogState();
}

class _MarkerEditDialogState extends State<_MarkerEditDialog> {
  late final TextEditingController _labelController;
  late final TextEditingController _noteController;
  late String _color;

  static const _colorOptions = <({String value, String label, IconData icon})>[
    (value: 'amber', label: 'Amber', icon: Icons.bookmark),
    (value: 'cyan', label: 'Cyan', icon: Icons.bookmark),
    (value: 'green', label: 'Green', icon: Icons.bookmark),
    (value: 'rose', label: 'Rose', icon: Icons.bookmark),
    (value: 'violet', label: 'Violet', icon: Icons.bookmark),
  ];

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(text: widget.marker.label);
    _noteController = TextEditingController(text: widget.marker.note);
    _color = widget.marker.color;
  }

  @override
  void dispose() {
    _labelController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('마커 편집'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('marker-label-field'),
              controller: _labelController,
              autofocus: true,
              maxLength: 32,
              decoration: const InputDecoration(
                labelText: '이름',
                prefixIcon: Icon(Icons.label_outline),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('marker-note-field'),
              controller: _noteController,
              maxLines: 3,
              maxLength: 160,
              decoration: const InputDecoration(
                labelText: '메모',
                prefixIcon: Icon(Icons.notes_outlined),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in _colorOptions)
                  ChoiceChip(
                    selected: _color == option.value,
                    onSelected: (_) => setState(() => _color = option.value),
                    avatar: Icon(
                      option.icon,
                      size: 16,
                      color: _timelineMarkerColor(colorScheme, option.value),
                    ),
                    label: Text(option.label),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () {
            final label = _labelController.text.trim();
            Navigator.of(context).pop(
              widget.marker.copyWith(
                label: label.isEmpty ? widget.marker.label : label,
                note: _noteController.text.trim(),
                color: _color,
              ),
            );
          },
          child: const Text('저장'),
        ),
      ],
    );
  }
}

Color _timelineMarkerColor(ColorScheme colorScheme, String color) {
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
