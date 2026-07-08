import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/job_models.dart';

class RenderOutputsPanel extends StatelessWidget {
  const RenderOutputsPanel({
    super.key,
    required this.outputs,
    this.compact = false,
  });

  final List<BatchRenderItemResult> outputs;
  final bool compact;

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
            _RenderOutputRow(output: outputs[index], compact: compact),
            if (index != outputs.length - 1) const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

class _RenderOutputRow extends StatelessWidget {
  const _RenderOutputRow({required this.output, required this.compact});

  final BatchRenderItemResult output;
  final bool compact;

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
              SelectableText(
                output.url,
                maxLines: compact ? 1 : 2,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colorScheme.primary),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        IconButton(
          tooltip: 'Copy render link',
          visualDensity: VisualDensity.compact,
          onPressed: () {
            Clipboard.setData(ClipboardData(text: output.url));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('$label link copied'),
                duration: const Duration(seconds: 1),
              ),
            );
          },
          icon: const Icon(Icons.copy, size: 16),
        ),
      ],
    );
  }
}
