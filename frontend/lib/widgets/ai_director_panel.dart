import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/editor_controller.dart';
import 'time_format.dart';

class AiDirectorPanel extends StatelessWidget {
  const AiDirectorPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<EditorController>();
    final colorScheme = Theme.of(context).colorScheme;
    final signals = controller.signalCounts;
    final selected = controller.selectedSegment;

    return ListView(
      children: [
        Row(
          children: [
            Icon(Icons.auto_fix_high, color: colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'AI Director',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            _ScoreBadge(score: controller.averageClipScore),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _MetricTile(
              icon: Icons.timer_outlined,
              label: 'Output',
              value: formatSeconds(controller.outputDurationSeconds),
            ),
            _MetricTile(
              icon: Icons.trending_down,
              label: 'Weak',
              value: '${controller.weakClipCount}',
            ),
            _MetricTile(
              icon: Icons.record_voice_over_outlined,
              label: 'Filler',
              value: '${controller.fillerCaptionCount}',
            ),
          ],
        ),
        const SizedBox(height: 14),
        _DirectorAction(
          icon: Icons.compress,
          title: 'Score Cut',
          value: '3-4m',
          enabled: controller.segments.length > 1,
          onPressed: () =>
              context.read<EditorController>().condenseTimelineByScore(),
        ),
        _DirectorAction(
          icon: Icons.filter_alt_off_outlined,
          title: 'Remove Weak',
          value: '${controller.weakClipCount}',
          enabled: controller.weakClipCount > 0,
          onPressed: context.read<EditorController>().removeWeakSegments,
        ),
        _DirectorAction(
          icon: Icons.center_focus_strong,
          title: 'Hook Pad',
          value: selected == null ? '-' : '±',
          enabled: selected != null,
          onPressed: context.read<EditorController>().padSelectedClipForContext,
        ),
        _DirectorAction(
          icon: Icons.voice_over_off_outlined,
          title: 'Filler Off',
          value: '${controller.fillerCaptionCount}',
          enabled: controller.fillerCaptionCount > 0,
          onPressed: context.read<EditorController>().hideFillerCaptions,
        ),
        _DirectorAction(
          icon: Icons.phone_iphone,
          title: 'Shorts Prep',
          value: '9:16',
          enabled: controller.duration > 0 && controller.segments.isNotEmpty,
          onPressed: context.read<EditorController>().applyShortsDirectorPreset,
        ),
        _DirectorAction(
          icon: Icons.tune,
          title: 'Finish Pass',
          value: 'Mix',
          enabled: controller.segments.isNotEmpty,
          onPressed: context.read<EditorController>().applyFinishingPreset,
        ),
        const SizedBox(height: 14),
        Text(
          'Signal Mix',
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        if (signals.isEmpty)
          _EmptySignal(colorScheme: colorScheme)
        else
          for (final entry in signals.entries)
            _SignalMeter(
              label: entry.key,
              count: entry.value,
              maxCount: signals.values.first,
            ),
      ],
    );
  }
}

class _DirectorAction extends StatelessWidget {
  const _DirectorAction({
    required this.icon,
    required this.title,
    required this.value,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String value;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: OutlinedButton(
        onPressed: enabled ? onPressed : null,
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 19),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(value, style: Theme.of(context).textTheme.labelSmall),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
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
      width: 100,
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        border: Border.all(color: colorScheme.outline),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: colorScheme.primary),
          const SizedBox(height: 5),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _ScoreBadge extends StatelessWidget {
  const _ScoreBadge({required this.score});

  final double score;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.14),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        score <= 0 ? 'No score' : score.toStringAsFixed(1),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: colorScheme.primary,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _SignalMeter extends StatelessWidget {
  const _SignalMeter({
    required this.label,
    required this.count,
    required this.maxCount,
  });

  final String label;
  final int count;
  final int maxCount;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final factor = maxCount <= 0 ? 0.0 : count / maxCount;
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
              Text('$count', style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
          const SizedBox(height: 5),
          LinearProgressIndicator(
            value: factor,
            minHeight: 6,
            borderRadius: BorderRadius.circular(6),
            backgroundColor: colorScheme.surfaceContainerHighest,
          ),
        ],
      ),
    );
  }
}

class _EmptySignal extends StatelessWidget {
  const _EmptySignal({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: colorScheme.outline),
      ),
      child: Text('No signal', style: Theme.of(context).textTheme.bodySmall),
    );
  }
}
