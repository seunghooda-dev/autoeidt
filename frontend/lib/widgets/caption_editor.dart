import 'package:flutter/material.dart';

import '../models/highlight_segment.dart';
import 'time_format.dart';

class CaptionEditor extends StatelessWidget {
  const CaptionEditor({
    super.key,
    required this.captions,
    required this.onChanged,
    required this.onToggle,
    required this.onSeek,
  });

  final List<CaptionSegment> captions;
  final ValueChanged<CaptionSegment> onChanged;
  final ValueChanged<CaptionSegment> onToggle;
  final ValueChanged<double> onSeek;

  @override
  Widget build(BuildContext context) {
    if (captions.isEmpty) {
      return Center(
        child: Text(
          '분석 후 자동 자막이 표시됩니다',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    return ListView.separated(
      itemCount: captions.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final caption = captions[index];
        final colorScheme = Theme.of(context).colorScheme;
        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            border: Border.all(color: colorScheme.outline),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Checkbox(
                    value: caption.enabled,
                    onChanged: (_) => onToggle(caption),
                  ),
                  Expanded(
                    child: Text(
                      '${formatSeconds(caption.start)} - ${formatSeconds(caption.end)}',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: '자막 위치로 이동',
                    onPressed: () => onSeek(caption.start),
                    icon: const Icon(Icons.play_arrow),
                  ),
                ],
              ),
              TextFormField(
                key: ValueKey(caption.order),
                initialValue: caption.text,
                enabled: caption.enabled,
                maxLines: 2,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  onChanged(caption.copyWith(text: value));
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
