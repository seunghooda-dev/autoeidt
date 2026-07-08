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
            _MetricTile(
              icon: Icons.construction_outlined,
              label: 'Fixes',
              value: '${controller.autoFixCount}',
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
        const _AutoFixQueuePanel(),
        const SizedBox(height: 14),
        const _ReferenceStylePanel(),
        const SizedBox(height: 14),
        const _MultiShortsPanel(),
        const SizedBox(height: 14),
        const _StyleReportPanel(),
        const SizedBox(height: 14),
        const _ComparisonPanel(),
        const SizedBox(height: 14),
        const _CaptionPresetPanel(),
        const SizedBox(height: 14),
        const _QualityReviewPanel(),
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

class _StyleReportPanel extends StatelessWidget {
  const _StyleReportPanel();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<EditorController>();
    final profile =
        controller.activeStyleProfile ?? controller.trainingStyleProfile;
    if (profile == null) {
      return const SizedBox.shrink();
    }
    final colorScheme = Theme.of(context).colorScheme;
    return _DirectorSection(
      title: 'Style Report',
      icon: Icons.analytics_outlined,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _MiniStat(label: 'Pace', value: profile.pace),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MiniStat(
                  label: 'Cut',
                  value: '${profile.averageCutSeconds.toStringAsFixed(1)}s',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  label: 'Hook',
                  value: '${profile.hookWindowSeconds.toStringAsFixed(0)}s',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MiniStat(
                  label: 'Silence',
                  value: '${(profile.silenceAggressiveness * 100).round()}%',
                ),
              ),
            ],
          ),
          if (profile.sources.isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${profile.readySourceCount}/${profile.sourceCount} references ready',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MultiShortsPanel extends StatelessWidget {
  const _MultiShortsPanel();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<EditorController>();
    final candidates = controller.shortsCandidates;
    final safetyBlocks = controller.selectedShortsRenderBlockCount;
    final safetyWarns = controller.selectedShortsRenderWarnCount;
    return _DirectorSection(
      title: 'Multi Shorts',
      icon: Icons.video_collection_outlined,
      trailing: candidates.isEmpty
          ? '0'
          : '${controller.selectedShortsCount}/${candidates.length}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: controller.segments.isEmpty
                      ? null
                      : context
                            .read<EditorController>()
                            .buildMultiShortsCandidates,
                  icon: const Icon(Icons.auto_awesome_motion, size: 17),
                  label: const Text('Build'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed:
                      candidates.isEmpty || controller.selectedShortsCount == 0
                      ? null
                      : context
                            .read<EditorController>()
                            .requestSelectedShortsRender,
                  icon: const Icon(Icons.ios_share, size: 17),
                  label: const Text('Render'),
                ),
              ),
            ],
          ),
          if (candidates.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: context
                        .read<EditorController>()
                        .updateSelectedShortsFromTimeline,
                    icon: const Icon(Icons.save_outlined, size: 17),
                    label: const Text('Update'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        controller.selectedShortsCount == 0 ||
                            !controller.hasSelectedShortsRenderSafetyIssues
                        ? null
                        : context
                              .read<EditorController>()
                              .applySelectedShortsRenderSafetyAutoRepair,
                    icon: const Icon(
                      Icons.health_and_safety_outlined,
                      size: 17,
                    ),
                    label: const Text('Make Safe'),
                  ),
                ),
              ],
            ),
            if (safetyBlocks > 0 || safetyWarns > 0) ...[
              const SizedBox(height: 6),
              Text(
                '$safetyBlocks render blocks · $safetyWarns warnings on selected',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: safetyBlocks > 0
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ] else if (controller.selectedShortsCount == 0) ...[
              const SizedBox(height: 6),
              Text(
                'No publish-ready shorts selected · review candidates manually',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 8),
            for (final candidate in candidates)
              _ShortsCandidateTile(candidate: candidate),
          ],
        ],
      ),
    );
  }
}

class _ShortsCandidateTile extends StatelessWidget {
  const _ShortsCandidateTile({required this.candidate});

  final ShortsCandidate candidate;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<EditorController>();
    final isActive = controller.selectedShortsId == candidate.id;
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      decoration: BoxDecoration(
        color: isActive
            ? colorScheme.primary.withValues(alpha: 0.12)
            : colorScheme.surface,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: isActive ? colorScheme.primary : colorScheme.outline,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: () => context.read<EditorController>().selectShortsCandidate(
          candidate.id,
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Checkbox(
                    value: candidate.selected,
                    onChanged: (_) => context
                        .read<EditorController>()
                        .toggleShortsCandidate(candidate.id),
                    visualDensity: VisualDensity.compact,
                  ),
                  Expanded(
                    child: Text(
                      candidate.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    formatSeconds(candidate.durationSeconds),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Wrap(
                spacing: 6,
                runSpacing: 5,
                children: [
                  _CandidateStrategyBadge(candidate: candidate),
                  _CandidateReadinessBadge(candidate: candidate),
                  _CandidateQualityBadge(candidate: candidate),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                candidate.reason,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall,
              ),
              if (candidate.storyFlow.isNotEmpty) ...[
                const SizedBox(height: 6),
                _StoryFlowStrip(candidate: candidate),
              ],
              const SizedBox(height: 5),
              Text(
                candidate.readinessDetail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: candidate.isPublishReady
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (candidate.strengths.isNotEmpty ||
                  candidate.issues.isNotEmpty) ...[
                const SizedBox(height: 7),
                Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: [
                    for (final item in candidate.strengths)
                      _CandidateChip(
                        label: item,
                        color: colorScheme.primary,
                        icon: Icons.check_circle_outline,
                      ),
                    for (final item in candidate.issues)
                      _CandidateChip(
                        label: item,
                        color: colorScheme.tertiary,
                        icon: Icons.warning_amber_outlined,
                      ),
                    if (candidate.riskCount > 0)
                      _CandidateChip(
                        label: 'Risk ${candidate.riskCount}',
                        color: colorScheme.error,
                        icon: Icons.report_gmailerrorred_outlined,
                      ),
                  ],
                ),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: 'Duplicate shorts candidate',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => context
                        .read<EditorController>()
                        .duplicateShortsCandidate(candidate.id),
                    icon: const Icon(Icons.copy, size: 16),
                  ),
                  IconButton(
                    tooltip: 'Delete shorts candidate',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => context
                        .read<EditorController>()
                        .deleteShortsCandidate(candidate.id),
                    icon: const Icon(Icons.delete_outline, size: 16),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StoryFlowStrip extends StatelessWidget {
  const _StoryFlowStrip({required this.candidate});

  static const _idealFlow = ['Hook', 'Evidence', 'Impact', 'Resolution'];

  final ShortsCandidate candidate;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final flow = candidate.storyFlow;
    final missing = [
      for (final role in _idealFlow)
        if (!flow.contains(role)) role,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              Icons.account_tree_outlined,
              size: 14,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                'Story Arc',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              'S${candidate.storyScore.round()}',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Wrap(
          spacing: 5,
          runSpacing: 5,
          children: [
            for (final role in flow)
              _StoryRoleChip(
                label: role,
                color: _storyRoleColor(colorScheme, role),
                active: true,
              ),
            for (final role in missing.take(2))
              _StoryRoleChip(
                label: role,
                color: colorScheme.outline,
                active: false,
              ),
          ],
        ),
      ],
    );
  }

  Color _storyRoleColor(ColorScheme colorScheme, String role) {
    return switch (role) {
      'Hook' => colorScheme.primary,
      'Context' => colorScheme.secondary,
      'Evidence' => colorScheme.tertiary,
      'Impact' => colorScheme.error,
      'Resolution' => colorScheme.primary,
      'Risk' => colorScheme.error,
      _ => colorScheme.outline,
    };
  }
}

class _StoryRoleChip extends StatelessWidget {
  const _StoryRoleChip({
    required this.label,
    required this.color,
    required this.active,
  });

  final String label;
  final Color color;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = active ? color : colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: active ? 0.11 : 0.04),
        border: Border.all(
          color: color.withValues(alpha: active ? 0.48 : 0.20),
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            active ? Icons.check_circle_outline : Icons.radio_button_unchecked,
            size: 11,
            color: foreground,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: active ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _CandidateStrategyBadge extends StatelessWidget {
  const _CandidateStrategyBadge({required this.candidate});

  final ShortsCandidate candidate;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = _strategyColor(colorScheme, candidate.strategyKind);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        border: Border.all(color: color.withValues(alpha: 0.52)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        candidate.strategyLabel,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Color _strategyColor(ColorScheme colorScheme, String strategyKind) {
    return switch (strategyKind) {
      'hook' => colorScheme.primary,
      'news' => colorScheme.secondary,
      'info' => colorScheme.tertiary,
      'risk' => colorScheme.error,
      _ => colorScheme.outline,
    };
  }
}

class _CandidateReadinessBadge extends StatelessWidget {
  const _CandidateReadinessBadge({required this.candidate});

  final ShortsCandidate candidate;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = switch (candidate.readinessLabel) {
      'Ready' => colorScheme.primary,
      'Review' => colorScheme.tertiary,
      _ => colorScheme.error,
    };
    return Tooltip(
      message: candidate.readinessDetail,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          border: Border.all(color: color.withValues(alpha: 0.58)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          candidate.readinessLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _CandidateQualityBadge extends StatelessWidget {
  const _CandidateQualityBadge({required this.candidate});

  final ShortsCandidate candidate;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = _gradeColor(colorScheme, candidate.qualityGrade);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        border: Border.all(color: color.withValues(alpha: 0.65)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '${candidate.qualityGrade} ${candidate.qualityScore.round()}',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w900,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }

  Color _gradeColor(ColorScheme colorScheme, String grade) {
    return switch (grade) {
      'S' => colorScheme.primary,
      'A' => colorScheme.primary,
      'B' => colorScheme.tertiary,
      'C' => colorScheme.outline,
      _ => colorScheme.error,
    };
  }
}

class _CandidateChip extends StatelessWidget {
  const _CandidateChip({
    required this.label,
    required this.color,
    required this.icon,
  });

  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        border: Border.all(color: color.withValues(alpha: 0.42)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ComparisonPanel extends StatelessWidget {
  const _ComparisonPanel();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<EditorController>();
    return _DirectorSection(
      title: 'A/B Compare',
      icon: Icons.compare_arrows,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: controller.segments.isEmpty
                      ? null
                      : context
                            .read<EditorController>()
                            .buildAiComparisonVariants,
                  icon: const Icon(Icons.alt_route, size: 17),
                  label: const Text('Build'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: controller.hasComparisonVariants
                      ? () => context
                            .read<EditorController>()
                            .applyComparisonVariant('reference')
                      : null,
                  icon: const Icon(Icons.auto_awesome, size: 17),
                  label: const Text('Ref B'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: controller.hasComparisonVariants
                ? () => context.read<EditorController>().applyComparisonVariant(
                    'default',
                  )
                : null,
            icon: const Icon(Icons.timeline, size: 17),
            label: Text(
              controller.hasComparisonVariants
                  ? 'Apply A · ${controller.comparisonDefaultSegments.length} clips'
                  : 'Apply A · no variant',
            ),
          ),
        ],
      ),
    );
  }
}

class _CaptionPresetPanel extends StatelessWidget {
  const _CaptionPresetPanel();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<EditorController>();
    return _DirectorSection(
      title: 'Caption Preset',
      icon: Icons.closed_caption_outlined,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final item in const [
            ('news', 'News'),
            ('shorts', 'Shorts'),
            ('minimal', 'Minimal'),
          ])
            ChoiceChip(
              selected: controller.captionStylePreset == item.$1,
              label: Text(item.$2),
              onSelected: (_) => context
                  .read<EditorController>()
                  .applyCaptionStylePreset(item.$1),
            ),
        ],
      ),
    );
  }
}

class _AutoFixQueuePanel extends StatelessWidget {
  const _AutoFixQueuePanel();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<EditorController>();
    final queue = controller.autoFixQueue;
    return _DirectorSection(
      title: 'Auto Fix Queue',
      icon: Icons.construction_outlined,
      trailing: queue.isEmpty ? 'clean' : '${queue.length}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: queue.isEmpty
                      ? null
                      : context.read<EditorController>().applyAllAutoFixes,
                  icon: const Icon(Icons.done_all, size: 17),
                  label: const Text('Fix All'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: queue.isEmpty
                      ? null
                      : () {
                          final item = queue.first;
                          context
                              .read<EditorController>()
                              .applyAutoFixForSegment(
                                item.segmentOrder,
                                item.action,
                              );
                        },
                  icon: const Icon(Icons.build_circle_outlined, size: 17),
                  label: const Text('Fix Top'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (queue.isEmpty)
            Text(
              '자동 수정할 컷 문제가 없습니다.',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          else
            for (final item in queue.take(6)) _AutoFixTile(item: item),
        ],
      ),
    );
  }
}

class _AutoFixTile extends StatelessWidget {
  const _AutoFixTile({required this.item});

  final AutoFixReviewItem item;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = _severityColor(colorScheme, item.severity);
    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.55)),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  'C${item.segmentOrder}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                _severityLabel(item.severity),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            item.detail,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => context
                  .read<EditorController>()
                  .applyAutoFixForSegment(item.segmentOrder, item.action),
              icon: Icon(
                item.action == AutoFixAction.selectForReview
                    ? Icons.visibility_outlined
                    : Icons.auto_fix_high,
                size: 16,
              ),
              label: Text(
                item.action == AutoFixAction.selectForReview ? 'Review' : 'Fix',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _severityColor(ColorScheme colorScheme, AutoFixSeverity severity) {
    return switch (severity) {
      AutoFixSeverity.block => colorScheme.error,
      AutoFixSeverity.warn => colorScheme.tertiary,
      AutoFixSeverity.polish => colorScheme.primary,
    };
  }

  String _severityLabel(AutoFixSeverity severity) {
    return switch (severity) {
      AutoFixSeverity.block => 'BLOCK',
      AutoFixSeverity.warn => 'WARN',
      AutoFixSeverity.polish => 'POLISH',
    };
  }
}

class _QualityReviewPanel extends StatelessWidget {
  const _QualityReviewPanel();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<EditorController>();
    final checks = controller.editorialChecklist;
    final safety = controller.renderSafetyChecklist;
    final visibleSafety = safety.take(7).toList();
    return _DirectorSection(
      title: 'Preflight',
      icon: Icons.fact_check_outlined,
      trailing:
          '${controller.renderSafetyBlockCount} gate · ${controller.editorialWarnCount + controller.renderSafetyWarnCount} warn',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: controller.segments.isEmpty
                      ? null
                      : context.read<EditorController>().applyAudioAutoMix,
                  icon: const Icon(Icons.graphic_eq, size: 17),
                  label: const Text('Audio Mix'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed:
                      controller.segments.isEmpty && controller.captions.isEmpty
                      ? null
                      : context
                            .read<EditorController>()
                            .applyEditorialReviewPass,
                  icon: const Icon(Icons.verified_outlined, size: 17),
                  label: const Text('QA Pass'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          if (controller.hasOfflineReviewSegments) ...[
            _OfflineReviewNotice(count: controller.offlineReviewSegmentCount),
            const SizedBox(height: 8),
          ],
          for (final check in checks) _CheckRow(check: check),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border.all(color: Theme.of(context).colorScheme.outline),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      controller.canPassRenderSafety
                          ? Icons.lock_open_outlined
                          : Icons.lock_outline,
                      size: 16,
                      color: controller.canPassRenderSafety
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        'Render Gate',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Text(
                      '${controller.renderSafetyBlockCount} block',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed:
                      controller.segments.isEmpty ||
                          (controller.renderSafetyBlockCount == 0 &&
                              controller.renderSafetyWarnCount == 0)
                      ? null
                      : context
                            .read<EditorController>()
                            .applyRenderSafetyAutoRepair,
                  icon: const Icon(Icons.health_and_safety_outlined, size: 17),
                  label: const Text('Make Safe'),
                ),
                const SizedBox(height: 8),
                for (final item in visibleSafety) _SafetyRow(item: item),
                if (safety.length > visibleSafety.length)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '+${safety.length - visibleSafety.length} more checks',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OfflineReviewNotice extends StatelessWidget {
  const _OfflineReviewNotice({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withValues(alpha: 0.10),
        border: Border.all(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.55),
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.manage_search_outlined,
            size: 17,
            color: Color(0xFFF59E0B),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$count offline review clips · STT/LLM 없이 만든 후보입니다',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DirectorSection extends StatelessWidget {
  const _DirectorSection({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.44),
        border: Border.all(color: colorScheme.outline),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              if (trailing != null)
                Text(trailing!, style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
          const SizedBox(height: 9),
          child,
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.check});

  final EditorialCheckItem check;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = switch (check.status) {
      EditorialCheckStatus.pass => colorScheme.primary,
      EditorialCheckStatus.warn => const Color(0xFFF59E0B),
      EditorialCheckStatus.block => colorScheme.error,
    };
    final icon = switch (check.status) {
      EditorialCheckStatus.pass => Icons.check_circle_outline,
      EditorialCheckStatus.warn => Icons.error_outline,
      EditorialCheckStatus.block => Icons.cancel_outlined,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              check.label,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          Flexible(
            child: Text(
              check.detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _SafetyRow extends StatelessWidget {
  const _SafetyRow({required this.item});

  final RenderSafetyItem item;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = switch (item.status) {
      EditorialCheckStatus.pass => colorScheme.primary,
      EditorialCheckStatus.warn => const Color(0xFFF59E0B),
      EditorialCheckStatus.block => colorScheme.error,
    };
    final icon = switch (item.status) {
      EditorialCheckStatus.pass => Icons.check_circle_outline,
      EditorialCheckStatus.warn => Icons.error_outline,
      EditorialCheckStatus.block => Icons.cancel_outlined,
    };
    final segmentOrder = item.segmentOrder;
    final row = Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              segmentOrder == null
                  ? item.label
                  : '${item.label}  #$segmentOrder',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              item.detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ],
      ),
    );

    if (segmentOrder == null) {
      return row;
    }
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () => context.read<EditorController>().selectSegment(segmentOrder),
      child: row,
    );
  }
}

class _ReferenceStylePanel extends StatefulWidget {
  const _ReferenceStylePanel();

  @override
  State<_ReferenceStylePanel> createState() => _ReferenceStylePanelState();
}

class _ReferenceStylePanelState extends State<_ReferenceStylePanel> {
  final TextEditingController _urlController = TextEditingController();

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<EditorController>();
    final colorScheme = Theme.of(context).colorScheme;
    final profile =
        controller.trainingStyleProfile ?? controller.activeStyleProfile;
    final progress = profile == null
        ? controller.styleUploadProgress
        : (profile.progress / 100).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.58),
        border: Border.all(color: colorScheme.outline),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.model_training, size: 18, color: colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Reference Style',
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                controller.hasReadyStyle ? 'ON' : 'OFF',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: controller.hasReadyStyle
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _urlController,
            minLines: 2,
            maxLines: 3,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Reference URLs',
              border: OutlineInputBorder(),
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: controller.isTrainingStyle
                      ? null
                      : context.read<EditorController>().pickReferenceVideos,
                  icon: const Icon(Icons.video_library_outlined, size: 17),
                  label: Text('Files ${controller.referenceFiles.length}'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: controller.isTrainingStyle
                      ? null
                      : () => context
                            .read<EditorController>()
                            .trainReferenceStyle(_urlController.text),
                  icon: const Icon(Icons.auto_awesome, size: 17),
                  label: const Text('Train'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              minHeight: 5,
              value: controller.isTrainingStyle && progress == 0
                  ? null
                  : progress,
              backgroundColor: colorScheme.surface,
            ),
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              Expanded(
                child: Text(
                  controller.styleStatusText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
              IconButton(
                tooltip: 'Clear reference style',
                visualDensity: VisualDensity.compact,
                onPressed:
                    controller.activeStyleProfile == null &&
                        controller.trainingStyleProfile == null &&
                        controller.referenceFiles.isEmpty
                    ? null
                    : context.read<EditorController>().clearReferenceStyle,
                icon: const Icon(Icons.close, size: 17),
              ),
            ],
          ),
        ],
      ),
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
