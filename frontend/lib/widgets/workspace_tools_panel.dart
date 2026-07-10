import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/editor_controller.dart';
import '../state/workspace_controller.dart';

class WorkspaceToolsPanel extends StatelessWidget {
  const WorkspaceToolsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final workspace = context.watch<WorkspaceController>();
    final editor = context.watch<EditorController>();
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(
                icon: Icon(Icons.dashboard_customize_outlined),
                text: 'Layout',
              ),
              Tab(icon: Icon(Icons.folder_outlined), text: 'Assets'),
              Tab(icon: Icon(Icons.history), text: 'History'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _LayoutTab(workspace: workspace),
                _AssetTab(workspace: workspace, editor: editor),
                _HistoryTab(workspace: workspace, editor: editor),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LayoutTab extends StatelessWidget {
  const _LayoutTab({required this.workspace});

  final WorkspaceController workspace;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Text(
          'Workspace presets',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final preset in WorkspaceController.presets)
              ChoiceChip(
                label: Text(preset.name),
                selected: workspace.activePreset == preset.name,
                onSelected: (_) => workspace.applyPreset(preset),
              ),
          ],
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: workspace.swapSidePanels,
          icon: const Icon(Icons.swap_horiz),
          label: Text(
            workspace.mediaOnLeft
                ? 'Media left · Inspector right'
                : 'Inspector left · Media right',
          ),
        ),
        const SizedBox(height: 14),
        _SizeSlider(
          label: 'Media panel',
          value: workspace.mediaWidth,
          min: 220,
          max: 460,
          onChanged: workspace.setMediaWidth,
          onChangeEnd: (value) =>
              workspace.finishPanelResize('Media panel', value),
        ),
        _SizeSlider(
          label: 'Inspector panel',
          value: workspace.inspectorWidth,
          min: 280,
          max: 520,
          onChanged: workspace.setInspectorWidth,
          onChangeEnd: (value) =>
              workspace.finishPanelResize('Inspector panel', value),
        ),
        _SizeSlider(
          label: 'Timeline',
          value: workspace.timelineHeight,
          min: 220,
          max: 520,
          onChanged: workspace.setTimelineHeight,
          onChangeEnd: (value) =>
              workspace.finishPanelResize('Timeline', value),
        ),
        const SizedBox(height: 10),
        Text(
          'Panel borders can also be dragged directly in the editor.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _SizeSlider extends StatelessWidget {
  const _SizeSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label  ${value.round()}px'),
        Slider(
          value: value,
          min: min,
          max: max,
          onChanged: onChanged,
          onChangeEnd: onChangeEnd,
        ),
      ],
    );
  }
}

class _AssetTab extends StatelessWidget {
  const _AssetTab({required this.workspace, required this.editor});

  final WorkspaceController workspace;
  final EditorController editor;

  static const folders = ['All', 'Unsorted', 'Footage', 'Audio', 'Graphics'];
  static const tags = ['Interview', 'B-roll', 'Music', 'News'];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
          child: Row(
            children: [
              Expanded(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: workspace.assetFolder,
                  items: folders
                      .map(
                        (value) =>
                            DropdownMenuItem(value: value, child: Text(value)),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      workspace.selectAssetFolder(value);
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                onPressed: () => _addAssetDialog(context),
                icon: const Icon(Icons.add),
                tooltip: 'Add asset',
              ),
            ],
          ),
        ),
        SizedBox(
          height: 42,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            scrollDirection: Axis.horizontal,
            children: [
              ChoiceChip(
                label: const Text('All tags'),
                selected: workspace.assetTagFilter.isEmpty,
                onSelected: (_) => workspace.selectAssetTag(''),
              ),
              const SizedBox(width: 6),
              for (final tag in tags) ...[
                ChoiceChip(
                  label: Text(tag),
                  selected: workspace.assetTagFilter == tag,
                  onSelected: (_) => workspace.selectAssetTag(tag),
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
        ),
        Expanded(
          child: workspace.filteredAssets.isEmpty
              ? const Center(child: Text('No assets in this view'))
              : ListView.builder(
                  itemCount: workspace.filteredAssets.length,
                  itemBuilder: (context, index) {
                    final asset = workspace.filteredAssets[index];
                    final isActive = editor.sourceMediaPath == asset.path;
                    return ListTile(
                      selected: isActive,
                      leading: Icon(
                        isActive
                            ? Icons.play_circle_outline
                            : Icons.movie_outlined,
                      ),
                      title: Text(
                        asset.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${asset.folder}  ${asset.tags.join(', ')}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => editor.openMediaPath(asset.path),
                      trailing: IconButton(
                        icon: const Icon(Icons.more_vert),
                        tooltip: 'Organize asset',
                        onPressed: () => _organizeAssetDialog(context, asset),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _addAssetDialog(BuildContext context) {
    final name = TextEditingController();
    final path = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add asset'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: path,
              decoration: const InputDecoration(labelText: 'Local path'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (name.text.trim().isNotEmpty && path.text.trim().isNotEmpty) {
                workspace.addAsset(
                  name: name.text.trim(),
                  path: path.text.trim(),
                );
              }
              Navigator.pop(context);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _organizeAssetDialog(BuildContext context, AssetEntry asset) {
    var selectedFolder = asset.folder;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(asset.name),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButton<String>(
                isExpanded: true,
                value: selectedFolder,
                items: folders
                    .where((folder) => folder != 'All')
                    .map(
                      (folder) =>
                          DropdownMenuItem(value: folder, child: Text(folder)),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => selectedFolder = value);
                    workspace.setAssetFolder(asset, value);
                  }
                },
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                children: [
                  for (final tag in tags)
                    FilterChip(
                      label: Text(tag),
                      selected: asset.tags.contains(tag),
                      onSelected: (_) {
                        setState(() => workspace.toggleAssetTag(asset, tag));
                      },
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton.icon(
              onPressed: () {
                workspace.removeAsset(asset);
                Navigator.pop(dialogContext);
              },
              icon: const Icon(Icons.delete_outline),
              label: const Text('Remove'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryTab extends StatelessWidget {
  const _HistoryTab({required this.workspace, required this.editor});

  final WorkspaceController workspace;
  final EditorController editor;

  @override
  Widget build(BuildContext context) {
    final editPoints = editor.editorHistoryPoints;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          children: [
            Text(
              'Edit timeline',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const Spacer(),
            Text('${editPoints.length} states'),
          ],
        ),
        const SizedBox(height: 8),
        for (var index = 0; index < editPoints.length; index++)
          _HistoryPointTile(
            point: editPoints[index],
            last: index == editPoints.length - 1,
            onRestore: editPoints[index].isCurrent
                ? null
                : () => editor.restoreHistoryDepth(editPoints[index].depth),
          ),
        const Divider(height: 28),
        Text(
          'Workspace activity',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        if (workspace.snapshots.isEmpty)
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('No workspace activity yet'),
          )
        else
          for (final item in workspace.snapshots.take(12))
            ListTile(
              dense: true,
              leading: const Icon(Icons.bookmark_outline),
              title: Text(item.label),
              subtitle: Text(item.detail),
              trailing: Text(_shortTime(item.createdAt)),
            ),
      ],
    );
  }
}

class _HistoryPointTile extends StatelessWidget {
  const _HistoryPointTile({
    required this.point,
    required this.last,
    required this.onRestore,
  });

  final EditorHistoryPoint point;
  final bool last;
  final VoidCallback? onRestore;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: point.isCurrent
                        ? colorScheme.primary
                        : colorScheme.outline,
                  ),
                ),
                if (!last)
                  Expanded(
                    child: Container(width: 1, color: colorScheme.outline),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListTile(
              dense: true,
              contentPadding: const EdgeInsets.only(left: 4),
              title: Text(point.label),
              subtitle: Text('${point.detail}\n${_shortTime(point.createdAt)}'),
              isThreeLine: true,
              trailing: onRestore == null
                  ? const Icon(Icons.radio_button_checked, size: 18)
                  : IconButton(
                      tooltip: 'Restore this edit state',
                      onPressed: onRestore,
                      icon: const Icon(Icons.restore, size: 19),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

String _shortTime(DateTime value) {
  final local = value.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}:'
      '${local.second.toString().padLeft(2, '0')}';
}
