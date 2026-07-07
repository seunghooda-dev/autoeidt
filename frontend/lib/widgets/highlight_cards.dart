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
        return Material(
          color: isSelected ? const Color(0xFFECFDF5) : Colors.white,
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
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : const Color(0xFFE5E7EB),
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
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${segment.order}. ${formatSeconds(segment.start)} - ${formatSeconds(segment.end)}',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      Text(
                        formatSeconds(segment.duration),
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ],
                  ),
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
                        color: const Color(0xFF4B5563),
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
