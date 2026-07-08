import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/job_models.dart';
import '../services/render_output_launcher.dart';
import 'time_format.dart';

class RenderOutputsPanel extends StatelessWidget {
  const RenderOutputsPanel({
    super.key,
    required this.outputs,
    this.compact = false,
    this.onRevealPath,
    this.onOpenPath,
  });

  final List<BatchRenderItemResult> outputs;
  final bool compact;
  final Future<void> Function(String path)? onRevealPath;
  final Future<void> Function(String path)? onOpenPath;

  @override
  Widget build(BuildContext context) {
    if (outputs.isEmpty) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.all(compact ? 9 : 11),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.18),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.32)),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.ios_share,
                size: compact ? 15 : 17,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  outputs.length == 1
                      ? 'Rendered output'
                      : 'Rendered outputs (${outputs.length})',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          for (var index = 0; index < outputs.length; index++) ...[
            _RenderOutputRow(
              output: outputs[index],
              compact: compact,
              onRevealPath: onRevealPath,
              onOpenPath: onOpenPath,
            ),
            if (index != outputs.length - 1) const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

class _RenderOutputRow extends StatelessWidget {
  const _RenderOutputRow({
    required this.output,
    required this.compact,
    required this.onRevealPath,
    required this.onOpenPath,
  });

  final BatchRenderItemResult output;
  final bool compact;
  final Future<void> Function(String path)? onRevealPath;
  final Future<void> Function(String path)? onOpenPath;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final label = output.outputName.isEmpty ? output.label : output.outputName;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.movie_creation_outlined,
          size: compact ? 14 : 16,
          color: colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              if (_metadataText.isNotEmpty)
                Text(
                  _metadataText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              SelectableText(
                output.url,
                maxLines: compact ? 1 : 2,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colorScheme.primary),
              ),
              if (output.path.isNotEmpty) ...[
                const SizedBox(height: 2),
                SelectableText(
                  output.path,
                  maxLines: compact ? 1 : 2,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 6),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Copy render link',
              visualDensity: VisualDensity.compact,
              onPressed: () => _copyValue(context, output.url, '$label link'),
              icon: const Icon(Icons.link, size: 16),
            ),
            if (output.path.isNotEmpty)
              IconButton(
                tooltip: 'Open rendered file',
                visualDensity: VisualDensity.compact,
                onPressed: () => _openFile(context, output.path, label),
                icon: const Icon(Icons.play_circle_outline, size: 16),
              ),
            if (output.path.isNotEmpty)
              IconButton(
                tooltip: 'Show in folder',
                visualDensity: VisualDensity.compact,
                onPressed: () => _revealFile(context, output.path, label),
                icon: const Icon(Icons.folder_open, size: 16),
              ),
            if (output.path.isNotEmpty)
              IconButton(
                tooltip: 'Copy local file path',
                visualDensity: VisualDensity.compact,
                onPressed: () =>
                    _copyValue(context, output.path, '$label file path'),
                icon: const Icon(Icons.folder_copy_outlined, size: 16),
              ),
          ],
        ),
      ],
    );
  }

  String get _metadataText {
    final parts = <String>[];
    if (output.durationSeconds > 0) {
      parts.add(formatSeconds(output.durationSeconds));
    }
    if (output.sizeBytes > 0) {
      parts.add(_formatBytes(output.sizeBytes));
    }
    return parts.join(' · ');
  }

  String _formatBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB'];
    var size = bytes.toDouble();
    var unitIndex = 0;
    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex += 1;
    }
    final precision = unitIndex == 0 || size >= 10 ? 0 : 1;
    return '${size.toStringAsFixed(precision)} ${units[unitIndex]}';
  }

  void _copyValue(BuildContext context, String value, String label) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _revealFile(
    BuildContext context,
    String path,
    String label,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final revealPath = onRevealPath ?? RenderOutputLauncher.reveal;
    try {
      await revealPath(path);
      messenger.showSnackBar(
        SnackBar(
          content: Text('$label location opened'),
          duration: const Duration(seconds: 1),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not open $label location: $error'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _openFile(
    BuildContext context,
    String path,
    String label,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final openPath = onOpenPath ?? RenderOutputLauncher.open;
    try {
      await openPath(path);
      messenger.showSnackBar(
        SnackBar(
          content: Text('$label opened'),
          duration: const Duration(seconds: 1),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not open $label: $error'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
}
