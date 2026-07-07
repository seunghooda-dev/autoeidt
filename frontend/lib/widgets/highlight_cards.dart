import 'package:flutter/material.dart';

import '../models/highlight_segment.dart';
import 'time_format.dart';

class HighlightCards extends StatelessWidget {
  const HighlightCards({
    super.key,
    required this.segments,
    required this.onSeek,
    required this.selectedOrder,
    required this.onSelect,
  });

  final List<HighlightSegment> segments;
  final ValueChanged<double> onSeek;
  final int? selectedOrder;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    if (segments.isEmpty) {
      return const SizedBox.shrink();
    }

    return ListView.separated(
      itemCount: segments.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final segment = segments[index];
        final isSelected = segment.order == selectedOrder;
        final colorScheme = Theme.of(context).colorScheme;
        return Material(
          color: isSelected
              ? colorScheme.primary.withValues(alpha: 0.16)
              : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              onSelect(segment.order);
              onSeek(segment.start);
            },
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                border: Border.all(
                  color: isSelected ? colorScheme.primary : colorScheme.outline,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.play_circle_outline,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${segment.order}. ${formatSeconds(segment.start)} - ${formatSeconds(segment.end)}',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      Text(
                        formatSeconds(segment.outputDuration),
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ],
                  ),
                  if (segment.score > 0 || segment.tags.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (segment.score > 0)
                          _SignalChip(
                            label: 'Score ${segment.score.toStringAsFixed(1)}',
                            color: colorScheme.primary,
                          ),
                        for (final tag in segment.tags.take(4))
                          _SignalChip(label: tag, color: colorScheme.tertiary),
                      ],
                    ),
                  ],
                  const SizedBox(height: 10),
                  Text(
                    segment.reason,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (segment.script.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      segment.script,
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
          ),
        );
      },
    );
  }
}

class _SignalChip extends StatelessWidget {
  const _SignalChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color.withValues(alpha: 0.44)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}
