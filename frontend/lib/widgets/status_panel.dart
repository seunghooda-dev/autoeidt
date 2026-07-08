import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/job_models.dart';
import '../state/editor_controller.dart';

class StatusPanel extends StatelessWidget {
  const StatusPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<EditorController>();
    final colorScheme = Theme.of(context).colorScheme;
    final progress = controller.isUploading
        ? controller.uploadProgress
        : ((controller.job?.progress ?? 0) / 100).clamp(0.0, 1.0);
    final jobStatus = controller.job?.status;
    final isActive =
        controller.isUploading ||
        controller.isProbingMedia ||
        jobStatus == 'queued' ||
        jobStatus == 'processing' ||
        jobStatus == 'rendering';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border.all(color: colorScheme.outline),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: colorScheme.outline),
                  ),
                  child: Icon(
                    Icons.video_library_outlined,
                    color: colorScheme.primary,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    controller.statusText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                if (controller.job != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: colorScheme.outline),
                    ),
                    child: Text(
                      '${controller.job!.progress}%',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                minHeight: 5,
                value: isActive && progress == 0 ? null : progress,
                backgroundColor: colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: controller.isUploading
                        ? null
                        : controller.pickVideo,
                    icon: const Icon(Icons.add),
                    label: const Text('Import'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: controller.canStartUpload
                        ? controller.startUpload
                        : null,
                    icon: const Icon(Icons.auto_awesome),
                    label: const Text('Analyze'),
                  ),
                ),
              ],
            ),
            if (controller.selectedMediaProbe != null) ...[
              const SizedBox(height: 12),
              _MediaProbePanel(probe: controller.selectedMediaProbe!),
            ],
            if (controller.job?.analysisWarnings.isNotEmpty ?? false) ...[
              const SizedBox(height: 12),
              _AnalysisWarnings(warnings: controller.job!.analysisWarnings),
            ],
            if (controller.renderUrl != null) ...[
              const SizedBox(height: 12),
              SelectableText(
                controller.renderUrl!,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colorScheme.primary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AnalysisWarnings extends StatelessWidget {
  const _AnalysisWarnings({required this.warnings});

  final List<String> warnings;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.tertiaryContainer.withValues(alpha: 0.22),
        border: Border.all(color: colorScheme.tertiary.withValues(alpha: 0.38)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final warning in warnings.take(2))
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 15, color: colorScheme.tertiary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    warning,
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _MediaProbePanel extends StatelessWidget {
  const _MediaProbePanel({required this.probe});

  final MediaProbeInfo probe;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final statusColor = probe.canAnalyze
        ? colorScheme.primary
        : colorScheme.error;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                probe.isMxf ? Icons.tv : Icons.fact_check,
                size: 16,
                color: statusColor,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  probe.isMxf ? 'MXF Media Check' : 'Media Check',
                  style: textTheme.labelMedium,
                ),
              ),
              Text(
                probe.canAnalyze ? 'Ready' : 'Blocked',
                style: textTheme.labelSmall?.copyWith(color: statusColor),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _ProbeBadge(
                label: probe.container.isEmpty ? 'container?' : probe.container,
              ),
              _ProbeBadge(label: probe.resolutionLabel),
              _ProbeBadge(
                label: probe.videoCodec.isEmpty ? 'codec?' : probe.videoCodec,
              ),
              _ProbeBadge(label: '${probe.frameRate.toStringAsFixed(3)} fps'),
              if (probe.timecode != null)
                _ProbeBadge(label: 'TC ${probe.timecode}'),
              _ProbeBadge(label: 'A ${probe.audioStreamCount}'),
            ],
          ),
          if (probe.isMxf && probe.mxfOperationalPattern.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              probe.mxfOperationalPattern,
              style: textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (probe.audioSummary.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              probe.audioSummary,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (probe.warnings.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final warning in probe.warnings.take(2))
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 14,
                      color: colorScheme.tertiary,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        warning,
                        style: textTheme.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _ProbeBadge extends StatelessWidget {
  const _ProbeBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}
