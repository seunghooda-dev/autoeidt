import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/job_models.dart';
import '../state/editor_controller.dart';
import '../state/workspace_controller.dart';

class WorkspaceToolsPanel extends StatelessWidget {
  const WorkspaceToolsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final workspace = context.watch<WorkspaceController>();
    final editor = context.watch<EditorController>();
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          TabBar(
            onTap: (index) {
              if (index == 2 &&
                  editor.recentJobs.isEmpty &&
                  !editor.isLoadingRecentJobs) {
                unawaited(editor.refreshRecentJobs());
              } else if (index == 3 &&
                  editor.storageUsage == null &&
                  !editor.isRefreshingStorage) {
                unawaited(editor.refreshStorageUsage());
              }
            },
            tabs: [
              const Tab(
                icon: Icon(Icons.dashboard_customize_outlined),
                text: 'Layout',
              ),
              const Tab(icon: Icon(Icons.folder_outlined), text: 'Assets'),
              const Tab(icon: Icon(Icons.history), text: 'History'),
              const Tab(icon: Icon(Icons.storage_outlined), text: 'Storage'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _LayoutTab(workspace: workspace),
                _AssetTab(workspace: workspace, editor: editor),
                _HistoryTab(workspace: workspace, editor: editor),
                _StorageTab(editor: editor),
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
            for (final preset in workspace.allPresets)
              InputChip(
                label: Text(preset.name),
                selected: workspace.activePreset == preset.name,
                onSelected: (_) => workspace.applyPreset(preset),
                onDeleted: workspace.customPresets.contains(preset)
                    ? () => workspace.deleteCustomPreset(preset)
                    : null,
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: workspace.toggleLayoutLock,
                icon: Icon(
                  workspace.layoutLocked ? Icons.lock : Icons.lock_open,
                ),
                label: Text(
                  workspace.layoutLocked ? 'Layout locked' : 'Lock layout',
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.outlined(
              tooltip: 'Save current workspace',
              onPressed: () => _savePresetDialog(context),
              icon: const Icon(Icons.save_outlined),
            ),
          ],
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: workspace.layoutLocked ? null : workspace.swapSidePanels,
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
          enabled: !workspace.layoutLocked,
        ),
        _SizeSlider(
          label: 'Inspector panel',
          value: workspace.inspectorWidth,
          min: 280,
          max: 520,
          onChanged: workspace.setInspectorWidth,
          onChangeEnd: (value) =>
              workspace.finishPanelResize('Inspector panel', value),
          enabled: !workspace.layoutLocked,
        ),
        _SizeSlider(
          label: 'Timeline',
          value: workspace.timelineHeight,
          min: 220,
          max: 520,
          onChanged: workspace.setTimelineHeight,
          onChangeEnd: (value) =>
              workspace.finishPanelResize('Timeline', value),
          enabled: !workspace.layoutLocked,
        ),
        const SizedBox(height: 10),
        Text(
          'Panel borders can also be dragged directly in the editor.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  void _savePresetDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Save workspace preset'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Preset name'),
          onSubmitted: (value) {
            workspace.saveCurrentPreset(value);
            Navigator.pop(dialogContext);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              workspace.saveCurrentPreset(controller.text);
              Navigator.pop(dialogContext);
            },
            child: const Text('Save'),
          ),
        ],
      ),
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
    this.enabled = true,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  final bool enabled;

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
          onChanged: enabled ? onChanged : null,
          onChangeEnd: enabled ? onChangeEnd : null,
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
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('asset-search-field'),
                  onChanged: workspace.setAssetSearchQuery,
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search assets',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                tooltip: 'Favorites only',
                isSelected: workspace.favoriteAssetsOnly,
                onPressed: workspace.toggleFavoriteAssetsOnly,
                icon: Icon(
                  workspace.favoriteAssetsOnly ? Icons.star : Icons.star_border,
                ),
              ),
            ],
          ),
        ),
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
                        asset.isOffline
                            ? Icons.link_off
                            : isActive
                            ? Icons.play_circle_outline
                            : Icons.movie_outlined,
                      ),
                      title: Text(
                        asset.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        asset.isOffline
                            ? 'Offline · ${asset.folder}'
                            : '${asset.folder}  ${asset.tags.join(', ')}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: asset.isOffline
                          ? null
                          : () => editor.openMediaPath(asset.path),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                              asset.favorite ? Icons.star : Icons.star_border,
                            ),
                            tooltip: asset.favorite
                                ? 'Remove favorite'
                                : 'Add favorite',
                            onPressed: () =>
                                workspace.toggleAssetFavorite(asset),
                          ),
                          IconButton(
                            icon: const Icon(Icons.more_vert),
                            tooltip: 'Organize asset',
                            onPressed: () =>
                                _organizeAssetDialog(context, asset),
                          ),
                        ],
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
              'Recent engine jobs',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const Spacer(),
            IconButton.outlined(
              tooltip: 'Refresh recent jobs',
              onPressed: editor.isLoadingRecentJobs || editor.isOpeningRecentJob
                  ? null
                  : () => editor.refreshRecentJobs(),
              icon: editor.isLoadingRecentJobs
                  ? const SizedBox.square(
                      dimension: 17,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 19),
            ),
          ],
        ),
        if (editor.recentJobsError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              editor.recentJobsError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          )
        else if (editor.recentJobs.isEmpty && !editor.isLoadingRecentJobs)
          const ListTile(
            dense: true,
            leading: Icon(Icons.history_toggle_off),
            title: Text('No engine jobs yet'),
          )
        else
          for (final recent in editor.recentJobs.take(8))
            _RecentJobTile(
              job: recent,
              current: editor.jobId == recent.jobId,
              opening: editor.isOpeningRecentJob,
              onOpen: () => _openRecentJob(context, recent),
            ),
        const Divider(height: 28),
        Row(
          children: [
            Text(
              'Saved versions',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: editor.hasRecoverableProject
                  ? () => _createSnapshotDialog(context)
                  : null,
              icon: const Icon(Icons.add, size: 17),
              label: const Text('Snapshot'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (editor.recoveryVersions.isEmpty)
          const ListTile(
            dense: true,
            leading: Icon(Icons.cloud_off_outlined),
            title: Text('No saved versions yet'),
          )
        else
          for (final version in editor.recoveryVersions)
            ListTile(
              dense: true,
              leading: Icon(
                version.isManual ? Icons.bookmark : Icons.cloud_done_outlined,
              ),
              title: Text(version.label),
              subtitle: Text(
                '${version.project.segments.length} clips · '
                '${_shortTime(version.savedAt)}',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Restore this version',
                    onPressed: () => editor.restoreRecoveryVersion(version.id),
                    icon: const Icon(Icons.restore, size: 19),
                  ),
                  IconButton(
                    tooltip: 'Delete this version',
                    onPressed: () => editor.deleteRecoveryVersion(version.id),
                    icon: const Icon(Icons.delete_outline, size: 19),
                  ),
                ],
              ),
            ),
        const Divider(height: 28),
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

  Future<void> _createSnapshotDialog(BuildContext context) async {
    final labelController = TextEditingController();
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Create project snapshot'),
          content: TextField(
            controller: labelController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Version label',
              hintText: 'Before final trim',
            ),
            onSubmitted: (value) {
              editor.createManualRecoverySnapshot(label: value);
              Navigator.pop(dialogContext);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                editor.createManualRecoverySnapshot(
                  label: labelController.text,
                );
                Navigator.pop(dialogContext);
              },
              child: const Text('Create'),
            ),
          ],
        ),
      );
    } finally {
      labelController.dispose();
    }
  }

  Future<void> _openRecentJob(
    BuildContext context,
    RecentJobSummary recent,
  ) async {
    if (editor.jobId == recent.jobId || editor.hasActiveJob) {
      return;
    }
    if (editor.hasUnsavedProjectChanges) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Open recent job?'),
          content: Text(
            'The current unsaved edit will remain in Auto Recovery. Open '
            '${recent.displayName} now?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Keep current'),
            ),
            FilledButton.icon(
              key: const Key('recent-job-confirm-open'),
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.history),
              label: const Text('Open job'),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) {
        return;
      }
    }
    final opened = await editor.resumeRecentJob(recent);
    if (opened && context.mounted) {
      Navigator.pop(context);
    }
  }
}

class _RecentJobTile extends StatelessWidget {
  const _RecentJobTile({
    required this.job,
    required this.current,
    required this.opening,
    required this.onOpen,
  });

  final RecentJobSummary job;
  final bool current;
  final bool opening;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = switch (job.status) {
      'rendered' || 'completed' => colorScheme.primary,
      'processing' || 'rendering' || 'queued' => colorScheme.tertiary,
      'failed' => colorScheme.error,
      _ => colorScheme.onSurfaceVariant,
    };
    final canOpen = job.canResume && !current && !opening;
    return ListTile(
      key: Key('recent-job-${job.jobId}'),
      dense: true,
      contentPadding: EdgeInsets.zero,
      enabled: canOpen,
      onTap: canOpen ? onOpen : null,
      leading: Icon(
        job.sourceExists
            ? job.renderExists
                  ? Icons.movie_filter_outlined
                  : Icons.video_file_outlined
            : job.renderExists || job.hasTimeline
            ? Icons.link_off
            : Icons.error_outline,
        color: statusColor,
      ),
      title: Text(
        job.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        _recentJobDetail(job),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: current
          ? const Chip(
              label: Text('Current'),
              visualDensity: VisualDensity.compact,
            )
          : IconButton(
              tooltip: job.canResume
                  ? 'Open recent job'
                  : 'Job files unavailable',
              onPressed: canOpen ? onOpen : null,
              icon: const Icon(Icons.open_in_new, size: 18),
            ),
    );
  }
}

String _recentJobDetail(RecentJobSummary job) {
  final parts = <String>[job.statusLabel];
  if (job.segmentCount > 0) {
    parts.add('${job.segmentCount} clips');
  }
  if (job.duration > 0) {
    parts.add(_shortDuration(job.duration));
  }
  if (!job.sourceExists) {
    parts.add('Source offline');
  }
  if (job.updatedAt != null) {
    parts.add(_shortJobTime(job.updatedAt!));
  }
  return parts.join(' · ');
}

String _shortDuration(double seconds) {
  final total = seconds.round().clamp(0, 359999);
  final hours = total ~/ 3600;
  final minutes = total.remainder(3600) ~/ 60;
  final remaining = total.remainder(60);
  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${remaining.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:'
      '${remaining.toString().padLeft(2, '0')}';
}

String _shortJobTime(DateTime value) {
  final local = value.toLocal();
  final now = DateTime.now();
  if (local.year == now.year &&
      local.month == now.month &&
      local.day == now.day) {
    return _shortTime(local);
  }
  return '${local.month.toString().padLeft(2, '0')}/'
      '${local.day.toString().padLeft(2, '0')} '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

class _StorageTab extends StatelessWidget {
  const _StorageTab({required this.editor});

  final EditorController editor;

  @override
  Widget build(BuildContext context) {
    final usage = editor.storageUsage;
    if (usage == null) {
      return Center(
        child: editor.isRefreshingStorage
            ? const CircularProgressIndicator()
            : FilledButton.icon(
                key: const Key('storage-load-button'),
                onPressed: editor.refreshStorageUsage,
                icon: const Icon(Icons.refresh),
                label: const Text('Load storage'),
              ),
      );
    }

    final reclaimRatio = usage.totalBytes <= 0
        ? 0.0
        : (usage.reclaimableBytes / usage.totalBytes)
              .clamp(0.0, 1.0)
              .toDouble();
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatStorageBytes(usage.totalBytes),
                    key: const Key('storage-total-value'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Text(
                    'AutoEdit local data',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            IconButton.outlined(
              tooltip: 'Refresh storage',
              onPressed: editor.isRefreshingStorage || editor.isCleaningStorage
                  ? null
                  : () => editor.refreshStorageUsage(),
              icon: editor.isRefreshingStorage
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 14),
        LinearProgressIndicator(
          value: reclaimRatio,
          minHeight: 6,
          borderRadius: BorderRadius.circular(3),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(Icons.cleaning_services_outlined, size: 17),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                '${_formatStorageBytes(usage.reclaimableBytes)} reclaimable',
                key: const Key('storage-reclaimable-value'),
              ),
            ),
            Text('>${usage.retentionHours}h old'),
          ],
        ),
        const Divider(height: 28),
        for (final category in usage.categories)
          _StorageCategoryTile(category: category),
        if (editor.storageErrorMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            editor.storageErrorMessage!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const Key('storage-clean-button'),
          onPressed: usage.reclaimableBytes <= 0 || editor.isCleaningStorage
              ? null
              : () => _confirmCleanup(context, usage),
          icon: editor.isCleaningStorage
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.cleaning_services_outlined),
          label: Text(
            editor.isCleaningStorage ? 'Cleaning...' : 'Clean safe cache',
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(
              Icons.verified_user_outlined,
              size: 17,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 7),
            const Expanded(
              child: Text('Sources, projects and exports protected'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _confirmCleanup(
    BuildContext context,
    StorageUsageInfo usage,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clean local cache?'),
        content: Text(
          '${_formatStorageBytes(usage.reclaimableBytes)} of preview and '
          'completed-analysis cache older than ${usage.retentionHours} hours '
          'will be removed. Imported sources, projects, current jobs and render '
          'outputs remain protected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            key: const Key('storage-confirm-clean-button'),
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.cleaning_services_outlined),
            label: const Text('Clean cache'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    final result = await editor.cleanupSafeStorage(
      retentionHours: usage.retentionHours,
    );
    if (result != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Freed ${_formatStorageBytes(result.freedBytes)} from '
            '${result.deletedFiles} cache files.',
          ),
        ),
      );
    }
  }
}

class _StorageCategoryTile extends StatelessWidget {
  const _StorageCategoryTile({required this.category});

  final StorageCategoryInfo category;

  @override
  Widget build(BuildContext context) {
    final icon = switch (category.key) {
      'preview_cache' => Icons.movie_filter_outlined,
      'analysis_cache' => Icons.analytics_outlined,
      'source_copies' => Icons.video_library_outlined,
      'render_outputs' => Icons.output_outlined,
      _ => Icons.description_outlined,
    };
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(category.label),
      subtitle: Text('${category.files} files'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (category.protected) ...[
            const Icon(Icons.lock_outline, size: 15),
            const SizedBox(width: 5),
          ],
          Text(_formatStorageBytes(category.bytes)),
        ],
      ),
    );
  }
}

String _formatStorageBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes < 0 ? 0.0 : bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }
  final digits = value >= 100 || unit == 0 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
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
