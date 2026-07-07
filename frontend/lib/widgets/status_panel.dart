import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
