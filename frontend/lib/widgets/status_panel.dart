import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/editor_controller.dart';

class StatusPanel extends StatelessWidget {
  const StatusPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<EditorController>();
    final progress = controller.isUploading
        ? controller.uploadProgress
        : ((controller.job?.progress ?? 0) / 100).clamp(0.0, 1.0);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    controller.statusText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (controller.job != null)
                  Text(
                    '${controller.job!.progress}%',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: progress == 0 ? null : progress),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: controller.isUploading ? null : controller.pickVideo,
                  icon: const Icon(Icons.video_file_outlined),
                  label: const Text('영상 선택'),
                ),
                OutlinedButton.icon(
                  onPressed: controller.canStartUpload ? controller.startUpload : null,
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: const Text('AI 분석 시작'),
                ),
              ],
            ),
            if (controller.renderUrl != null) ...[
              const SizedBox(height: 12),
              SelectableText(
                controller.renderUrl!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
