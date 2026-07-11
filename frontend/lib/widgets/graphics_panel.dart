import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/highlight_segment.dart';
import '../state/editor_controller.dart';
import 'time_format.dart';

class GraphicsPanel extends StatelessWidget {
  const GraphicsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<EditorController>();
    final editor = context.read<EditorController>();
    final selected = controller.selectedGraphicClip;
    final canAdd =
        controller.segments.isNotEmpty && !controller.graphicsTrackLocked;
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.title, color: colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Broadcast Graphics',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              key: const Key('graphics-track-visibility'),
              tooltip: controller.graphicsTrackVisible
                  ? 'G1 트랙 숨기기'
                  : 'G1 트랙 표시',
              onPressed: editor.toggleGraphicsTrackVisibility,
              icon: Icon(
                controller.graphicsTrackVisible
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
            ),
            IconButton(
              key: const Key('graphics-track-lock'),
              tooltip: controller.graphicsTrackLocked ? 'G1 잠금 해제' : 'G1 잠금',
              onPressed: editor.toggleGraphicsTrackLock,
              icon: Icon(
                controller.graphicsTrackLocked
                    ? Icons.lock
                    : Icons.lock_open_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _AddGraphicButton(
              key: const Key('add-lower-third'),
              label: 'Lower third',
              icon: Icons.subtitles_outlined,
              enabled: canAdd,
              onPressed: () => editor.addGraphicClip('lower_third'),
            ),
            _AddGraphicButton(
              key: const Key('add-headline'),
              label: 'Headline',
              icon: Icons.newspaper_outlined,
              enabled: canAdd,
              onPressed: () => editor.addGraphicClip('headline'),
            ),
            _AddGraphicButton(
              key: const Key('add-corner-bug'),
              label: 'Corner bug',
              icon: Icons.live_tv_outlined,
              enabled: canAdd,
              onPressed: () => editor.addGraphicClip('corner_bug'),
            ),
          ],
        ),
        if (!canAdd && controller.segments.isEmpty) ...[
          const SizedBox(height: 8),
          Text(
            '시퀀스를 만든 뒤 그래픽을 추가할 수 있습니다.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 12),
        Expanded(
          child: controller.graphics.isEmpty
              ? Center(
                  child: Text(
                    'G1 트랙에 그래픽이 없습니다',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                )
              : ListView.separated(
                  itemCount: controller.graphics.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final graphic = controller.graphics[index];
                    return _GraphicListItem(
                      graphic: graphic,
                      selected: selected?.id == graphic.id,
                      trackLocked: controller.graphicsTrackLocked,
                      onSelect: () {
                        editor.selectGraphicClip(graphic.id);
                        editor.seekMonitorTo(
                          graphic.timelineStart,
                          autoplay: false,
                        );
                      },
                      onToggle: () {
                        editor.selectGraphicClip(graphic.id);
                        editor.toggleSelectedGraphicEnabled();
                      },
                    );
                  },
                ),
        ),
        if (selected != null) ...[
          const Divider(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${_presetLabel(selected.preset)} · ${formatSeconds(selected.timelineStart)} - ${formatSeconds(selected.timelineEnd)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
              IconButton(
                key: const Key('duplicate-selected-graphic'),
                tooltip: '그래픽 복제',
                onPressed: controller.graphicsTrackLocked
                    ? null
                    : editor.duplicateSelectedGraphicClip,
                icon: const Icon(Icons.copy_outlined),
              ),
              IconButton(
                key: const Key('delete-selected-graphic'),
                tooltip: '그래픽 삭제',
                onPressed: controller.graphicsTrackLocked
                    ? null
                    : editor.deleteSelectedGraphicClip,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _AddGraphicButton extends StatelessWidget {
  const _AddGraphicButton({
    super.key,
    required this.label,
    required this.icon,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: enabled ? onPressed : null,
      icon: Icon(icon, size: 17),
      label: Text(label),
    );
  }
}

class _GraphicListItem extends StatelessWidget {
  const _GraphicListItem({
    required this.graphic,
    required this.selected,
    required this.trackLocked,
    required this.onSelect,
    required this.onToggle,
  });

  final GraphicClip graphic;
  final bool selected;
  final bool trackLocked;
  final VoidCallback onSelect;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? colorScheme.primaryContainer.withValues(alpha: 0.28)
          : colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(
          color: selected ? colorScheme.primary : colorScheme.outline,
        ),
      ),
      child: InkWell(
        key: ValueKey('graphic-list-${graphic.id}'),
        borderRadius: BorderRadius.circular(4),
        onTap: onSelect,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          child: Row(
            children: [
              Icon(
                graphic.preset == 'corner_bug'
                    ? Icons.live_tv_outlined
                    : Icons.title,
                size: 18,
                color: graphic.enabled
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      graphic.headline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    Text(
                      '${_presetLabel(graphic.preset)} · ${formatSeconds(graphic.timelineStart)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: graphic.enabled ? '그래픽 비활성화' : '그래픽 활성화',
                visualDensity: VisualDensity.compact,
                onPressed: trackLocked ? null : onToggle,
                icon: Icon(
                  graphic.enabled
                      ? Icons.check_circle_outline
                      : Icons.block_outlined,
                  size: 18,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _presetLabel(String preset) => switch (preset) {
  'headline' => 'Headline',
  'corner_bug' => 'Corner bug',
  _ => 'Lower third',
};
