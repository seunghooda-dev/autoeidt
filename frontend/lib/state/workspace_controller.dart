import 'package:flutter/foundation.dart';

class WorkspacePreset {
  const WorkspacePreset({required this.name, required this.mediaWidth, required this.inspectorWidth, required this.timelineHeight});
  final String name;
  final double mediaWidth;
  final double inspectorWidth;
  final double timelineHeight;
}

class WorkspaceSnapshot {
  const WorkspaceSnapshot({required this.label, required this.detail, required this.createdAt});
  final String label;
  final String detail;
  final DateTime createdAt;
}

class AssetEntry {
  AssetEntry({required this.name, required this.path, this.folder = 'Unsorted', Set<String>? tags}) : tags = Set<String>.of(tags ?? const {});
  final String name;
  final String path;
  String folder;
  final Set<String> tags;
}

class WorkspaceController extends ChangeNotifier {
  double mediaWidth = 320;
  double inspectorWidth = 372;
  double timelineHeight = 342;
  String activePreset = 'Edit';
  String assetFolder = 'Unsorted';
  String assetTagFilter = '';
  final List<AssetEntry> assets = [];
  final List<WorkspaceSnapshot> snapshots = [];

  static const presets = <WorkspacePreset>[
    WorkspacePreset(name: 'Edit', mediaWidth: 320, inspectorWidth: 372, timelineHeight: 342),
    WorkspacePreset(name: 'Color', mediaWidth: 220, inspectorWidth: 470, timelineHeight: 300),
    WorkspacePreset(name: 'Audio', mediaWidth: 250, inspectorWidth: 430, timelineHeight: 410),
    WorkspacePreset(name: 'Review', mediaWidth: 380, inspectorWidth: 300, timelineHeight: 280),
  ];

  void setMediaWidth(double value) { mediaWidth = value.clamp(220, 460); record('Media panel resized', '${mediaWidth.round()} px'); }
  void setInspectorWidth(double value) { inspectorWidth = value.clamp(280, 520); record('Inspector panel resized', '${inspectorWidth.round()} px'); }
  void setTimelineHeight(double value) { timelineHeight = value.clamp(220, 520); record('Timeline resized', '${timelineHeight.round()} px'); }

  void applyPreset(WorkspacePreset preset) {
    activePreset = preset.name;
    mediaWidth = preset.mediaWidth;
    inspectorWidth = preset.inspectorWidth;
    timelineHeight = preset.timelineHeight;
    record('Workspace applied', preset.name);
  }

  void addAsset({required String name, required String path}) {
    if (assets.any((asset) => asset.path == path)) return;
    assets.add(AssetEntry(name: name, path: path));
    notifyListeners();
  }

  void setAssetFolder(AssetEntry asset, String folder) { asset.folder = folder; notifyListeners(); }
  void selectAssetFolder(String folder) { assetFolder = folder; notifyListeners(); }
  void toggleAssetTag(AssetEntry asset, String tag) { asset.tags.contains(tag) ? asset.tags.remove(tag) : asset.tags.add(tag); notifyListeners(); }

  List<AssetEntry> get filteredAssets => assets.where((asset) =>
      (assetFolder == 'All' || asset.folder == assetFolder) &&
      (assetTagFilter.isEmpty || asset.tags.contains(assetTagFilter))).toList();

  void record(String label, String detail) {
    snapshots.insert(0, WorkspaceSnapshot(label: label, detail: detail, createdAt: DateTime.now()));
    if (snapshots.length > 40) snapshots.removeLast();
    notifyListeners();
  }
}
