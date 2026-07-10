import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/workspace_controller.dart';

class WorkspaceToolsPanel extends StatelessWidget {
  const WorkspaceToolsPanel({super.key});
  @override
  Widget build(BuildContext context) {
    final workspace = context.watch<WorkspaceController>();
    return DefaultTabController(length: 3, child: Column(children: [
      const TabBar(tabs: [Tab(icon: Icon(Icons.dashboard_customize_outlined), text: 'Layout'), Tab(icon: Icon(Icons.folder_outlined), text: 'Assets'), Tab(icon: Icon(Icons.history), text: 'History')]),
      Expanded(child: TabBarView(children: [
        _LayoutTab(workspace: workspace),
        _AssetTab(workspace: workspace),
        _HistoryTab(workspace: workspace),
      ])),
    ]));
  }
}

class _LayoutTab extends StatelessWidget {
  const _LayoutTab({required this.workspace});
  final WorkspaceController workspace;
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(12), children: [
    Text('Workspace presets', style: Theme.of(context).textTheme.titleSmall),
    const SizedBox(height: 8),
    Wrap(spacing: 6, runSpacing: 6, children: [for (final preset in WorkspaceController.presets) ChoiceChip(label: Text(preset.name), selected: workspace.activePreset == preset.name, onSelected: (_) => workspace.applyPreset(preset))]),
    const SizedBox(height: 18),
    _SizeSlider(label: 'Media panel', value: workspace.mediaWidth, min: 220, max: 460, onChanged: workspace.setMediaWidth),
    _SizeSlider(label: 'Inspector panel', value: workspace.inspectorWidth, min: 280, max: 520, onChanged: workspace.setInspectorWidth),
    _SizeSlider(label: 'Timeline', value: workspace.timelineHeight, min: 220, max: 520, onChanged: workspace.setTimelineHeight),
    const SizedBox(height: 12),
    Text('Drag panel borders in the editor to resize.', style: Theme.of(context).textTheme.bodySmall),
  ]);
}

class _SizeSlider extends StatelessWidget {
  const _SizeSlider({required this.label, required this.value, required this.min, required this.max, required this.onChanged});
  final String label; final double value; final double min; final double max; final ValueChanged<double> onChanged;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('$label  ${value.round()}px'), Slider(value: value, min: min, max: max, onChanged: onChanged)]);
}

class _AssetTab extends StatelessWidget {
  const _AssetTab({required this.workspace});
  final WorkspaceController workspace;
  @override
  Widget build(BuildContext context) => Column(children: [
    Padding(padding: const EdgeInsets.all(10), child: Row(children: [Expanded(child: DropdownButton<String>(isExpanded: true, value: workspace.assetFolder, items: ['All', 'Unsorted', 'Footage', 'Audio', 'Graphics'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: (v) { if (v != null) workspace.selectAssetFolder(v); })), IconButton(onPressed: () => _addAssetDialog(context), icon: const Icon(Icons.add), tooltip: 'Add asset')])),
    Expanded(child: ListView(children: [for (final asset in workspace.filteredAssets) ListTile(leading: const Icon(Icons.movie_outlined), title: Text(asset.name, maxLines: 1, overflow: TextOverflow.ellipsis), subtitle: Text('${asset.folder}  ${asset.tags.join(', ')}'), onTap: () => _tagDialog(context, asset))])),
  ]);
  void _addAssetDialog(BuildContext context) { final name = TextEditingController(); final path = TextEditingController(); showDialog(context: context, builder: (_) => AlertDialog(title: const Text('Add asset'), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')), TextField(controller: path, decoration: const InputDecoration(labelText: 'Path'))]), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: () { if (name.text.trim().isNotEmpty && path.text.trim().isNotEmpty) workspace.addAsset(name: name.text.trim(), path: path.text.trim()); Navigator.pop(context); }, child: const Text('Add'))])); }
  void _tagDialog(BuildContext context, AssetEntry asset) { showDialog(context: context, builder: (_) => AlertDialog(title: Text(asset.name), content: Wrap(spacing: 6, children: [for (final tag in ['Interview', 'B-roll', 'Music', 'News']) FilterChip(label: Text(tag), selected: asset.tags.contains(tag), onSelected: (_) => workspace.toggleAssetTag(asset, tag))]), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))])); }
}

class _HistoryTab extends StatelessWidget {
  const _HistoryTab({required this.workspace});
  final WorkspaceController workspace;
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(10), children: [if (workspace.snapshots.isEmpty) const ListTile(leading: Icon(Icons.info_outline), title: Text('No snapshots yet')) else for (final item in workspace.snapshots) ListTile(leading: const Icon(Icons.bookmark_outline), title: Text(item.label), subtitle: Text('${item.detail}\n${item.createdAt.toLocal()}'), isThreeLine: true)]);
}
