import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter/foundation.dart';

class WorkspacePreset {
  const WorkspacePreset({
    required this.name,
    required this.mediaWidth,
    required this.inspectorWidth,
    required this.timelineHeight,
    this.mediaOnLeft = true,
  });

  final String name;
  final double mediaWidth;
  final double inspectorWidth;
  final double timelineHeight;
  final bool mediaOnLeft;

  Map<String, dynamic> toJson() => {
    'name': name,
    'media_width': mediaWidth,
    'inspector_width': inspectorWidth,
    'timeline_height': timelineHeight,
    'media_on_left': mediaOnLeft,
  };

  factory WorkspacePreset.fromJson(Map<String, dynamic> json) {
    return WorkspacePreset(
      name: json['name'] as String? ?? 'Custom',
      mediaWidth: (json['media_width'] as num?)?.toDouble() ?? 320,
      inspectorWidth: (json['inspector_width'] as num?)?.toDouble() ?? 372,
      timelineHeight: (json['timeline_height'] as num?)?.toDouble() ?? 342,
      mediaOnLeft: json['media_on_left'] as bool? ?? true,
    );
  }
}

class WorkspaceSnapshot {
  const WorkspaceSnapshot({
    required this.label,
    required this.detail,
    required this.createdAt,
  });

  final String label;
  final String detail;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'label': label,
    'detail': detail,
    'created_at': createdAt.toIso8601String(),
  };

  factory WorkspaceSnapshot.fromJson(Map<String, dynamic> json) {
    return WorkspaceSnapshot(
      label: json['label'] as String? ?? 'Workspace change',
      detail: json['detail'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

class AssetEntry {
  AssetEntry({
    required this.name,
    required this.path,
    this.folder = 'Unsorted',
    this.favorite = false,
    Set<String>? tags,
  }) : tags = Set<String>.of(tags ?? const {});

  final String name;
  final String path;
  String folder;
  bool favorite;
  final Set<String> tags;

  bool get isOffline => !kIsWeb && !io.File(path).existsSync();

  Map<String, dynamic> toJson() => {
    'name': name,
    'path': path,
    'folder': folder,
    'favorite': favorite,
    'tags': tags.toList()..sort(),
  };

  factory AssetEntry.fromJson(Map<String, dynamic> json) {
    return AssetEntry(
      name: json['name'] as String? ?? 'Media',
      path: json['path'] as String? ?? '',
      folder: json['folder'] as String? ?? 'Unsorted',
      favorite: json['favorite'] as bool? ?? false,
      tags: (json['tags'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toSet(),
    );
  }
}

class WorkspaceController extends ChangeNotifier {
  WorkspaceController({bool persist = true, String? storagePath})
    : _persist = persist && !kIsWeb,
      _storagePath = storagePath {
    if (_persist) {
      unawaited(load());
    }
  }

  final bool _persist;
  final String? _storagePath;
  Timer? _saveTimer;
  bool _disposed = false;

  double mediaWidth = 320;
  double inspectorWidth = 372;
  double timelineHeight = 342;
  bool mediaOnLeft = true;
  bool layoutLocked = false;
  String activePanel = 'preview';
  String? maximizedPanel;
  String activePreset = 'Edit';
  String assetFolder = 'All';
  String assetTagFilter = '';
  String assetSearchQuery = '';
  bool favoriteAssetsOnly = false;
  final List<AssetEntry> assets = [];
  final List<WorkspaceSnapshot> snapshots = [];
  final List<WorkspacePreset> customPresets = [];

  static const presets = <WorkspacePreset>[
    WorkspacePreset(
      name: 'Edit',
      mediaWidth: 320,
      inspectorWidth: 372,
      timelineHeight: 342,
    ),
    WorkspacePreset(
      name: 'Color',
      mediaWidth: 220,
      inspectorWidth: 470,
      timelineHeight: 300,
    ),
    WorkspacePreset(
      name: 'Audio',
      mediaWidth: 250,
      inspectorWidth: 430,
      timelineHeight: 410,
    ),
    WorkspacePreset(
      name: 'Review',
      mediaWidth: 380,
      inspectorWidth: 300,
      timelineHeight: 280,
      mediaOnLeft: false,
    ),
  ];

  List<WorkspacePreset> get allPresets => [...presets, ...customPresets];

  void setMediaWidth(double value, {bool recordChange = false}) {
    if (layoutLocked) {
      return;
    }
    mediaWidth = value.clamp(220, 460);
    _changed();
    if (recordChange) {
      record('Media panel resized', '${mediaWidth.round()} px');
    }
  }

  void setInspectorWidth(double value, {bool recordChange = false}) {
    if (layoutLocked) {
      return;
    }
    inspectorWidth = value.clamp(280, 520);
    _changed();
    if (recordChange) {
      record('Inspector panel resized', '${inspectorWidth.round()} px');
    }
  }

  void setTimelineHeight(double value, {bool recordChange = false}) {
    if (layoutLocked) {
      return;
    }
    timelineHeight = value.clamp(220, 520);
    _changed();
    if (recordChange) {
      record('Timeline resized', '${timelineHeight.round()} px');
    }
  }

  void finishPanelResize(String panelName, double value) {
    if (layoutLocked) {
      return;
    }
    record('$panelName resized', '${value.round()} px');
  }

  void applyPreset(WorkspacePreset preset) {
    activePreset = preset.name;
    mediaWidth = preset.mediaWidth;
    inspectorWidth = preset.inspectorWidth;
    timelineHeight = preset.timelineHeight;
    mediaOnLeft = preset.mediaOnLeft;
    record('Workspace applied', preset.name);
  }

  void swapSidePanels() {
    if (layoutLocked) {
      return;
    }
    mediaOnLeft = !mediaOnLeft;
    activePreset = 'Custom';
    record(
      'Panel positions swapped',
      mediaOnLeft
          ? 'Media left / Inspector right'
          : 'Inspector left / Media right',
    );
  }

  void toggleLayoutLock() {
    layoutLocked = !layoutLocked;
    record('Workspace ${layoutLocked ? 'locked' : 'unlocked'}', activePreset);
  }

  void setActivePanel(String panel) {
    if (activePanel == panel) {
      return;
    }
    activePanel = panel;
    _notify();
  }

  void toggleMaximizeActivePanel() {
    maximizedPanel = maximizedPanel == null ? activePanel : null;
    record(
      maximizedPanel == null ? 'Panel restored' : 'Panel maximized',
      maximizedPanel ?? activePanel,
    );
  }

  void saveCurrentPreset(String name) {
    final normalized = name.trim();
    if (normalized.isEmpty) {
      return;
    }
    customPresets.removeWhere(
      (preset) => preset.name.toLowerCase() == normalized.toLowerCase(),
    );
    customPresets.add(
      WorkspacePreset(
        name: normalized,
        mediaWidth: mediaWidth,
        inspectorWidth: inspectorWidth,
        timelineHeight: timelineHeight,
        mediaOnLeft: mediaOnLeft,
      ),
    );
    activePreset = normalized;
    record('Custom workspace saved', normalized);
  }

  void deleteCustomPreset(WorkspacePreset preset) {
    if (customPresets.remove(preset)) {
      if (activePreset == preset.name) {
        activePreset = 'Custom';
      }
      record('Custom workspace deleted', preset.name);
    }
  }

  void addAsset({required String name, required String path}) {
    if (path.trim().isEmpty || assets.any((asset) => asset.path == path)) {
      return;
    }
    assets.add(AssetEntry(name: name, path: path));
    record('Asset added', name);
  }

  void removeAsset(AssetEntry asset) {
    assets.remove(asset);
    record('Asset removed', asset.name);
  }

  void setAssetFolder(AssetEntry asset, String folder) {
    asset.folder = folder;
    record('Asset moved', '${asset.name} -> $folder');
  }

  void selectAssetFolder(String folder) {
    assetFolder = folder;
    _changed();
  }

  void selectAssetTag(String tag) {
    assetTagFilter = tag;
    _changed();
  }

  void toggleAssetTag(AssetEntry asset, String tag) {
    asset.tags.contains(tag) ? asset.tags.remove(tag) : asset.tags.add(tag);
    record('Asset tags changed', '${asset.name}: ${asset.tags.join(', ')}');
  }

  void toggleAssetFavorite(AssetEntry asset) {
    asset.favorite = !asset.favorite;
    record(
      asset.favorite ? 'Asset favorited' : 'Asset unfavorited',
      asset.name,
    );
  }

  void setAssetSearchQuery(String query) {
    assetSearchQuery = query.trim().toLowerCase();
    _notify();
  }

  void toggleFavoriteAssetsOnly() {
    favoriteAssetsOnly = !favoriteAssetsOnly;
    _notify();
  }

  List<AssetEntry> get filteredAssets => assets
      .where(
        (asset) =>
            (assetFolder == 'All' || asset.folder == assetFolder) &&
            (assetTagFilter.isEmpty || asset.tags.contains(assetTagFilter)) &&
            (!favoriteAssetsOnly || asset.favorite) &&
            (assetSearchQuery.isEmpty ||
                asset.name.toLowerCase().contains(assetSearchQuery) ||
                asset.path.toLowerCase().contains(assetSearchQuery) ||
                asset.tags.any(
                  (tag) => tag.toLowerCase().contains(assetSearchQuery),
                )),
      )
      .toList();

  void record(String label, String detail) {
    snapshots.insert(
      0,
      WorkspaceSnapshot(
        label: label,
        detail: detail,
        createdAt: DateTime.now(),
      ),
    );
    if (snapshots.length > 40) {
      snapshots.removeLast();
    }
    _changed();
  }

  Future<void> load() async {
    try {
      final file = io.File(_resolvedStoragePath);
      if (!await file.exists()) {
        return;
      }
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      mediaWidth = ((json['media_width'] as num?)?.toDouble() ?? mediaWidth)
          .clamp(220, 460);
      inspectorWidth =
          ((json['inspector_width'] as num?)?.toDouble() ?? inspectorWidth)
              .clamp(280, 520);
      timelineHeight =
          ((json['timeline_height'] as num?)?.toDouble() ?? timelineHeight)
              .clamp(220, 520);
      mediaOnLeft = json['media_on_left'] as bool? ?? mediaOnLeft;
      layoutLocked = json['layout_locked'] as bool? ?? layoutLocked;
      activePreset = json['active_preset'] as String? ?? activePreset;
      customPresets
        ..clear()
        ..addAll(
          (json['custom_presets'] as List<dynamic>? ?? const [])
              .whereType<Map>()
              .map(
                (item) =>
                    WorkspacePreset.fromJson(Map<String, dynamic>.from(item)),
              ),
        );
      assets
        ..clear()
        ..addAll(
          (json['assets'] as List<dynamic>? ?? const [])
              .whereType<Map>()
              .map(
                (item) => AssetEntry.fromJson(Map<String, dynamic>.from(item)),
              )
              .where((asset) => asset.path.isNotEmpty),
        );
      snapshots
        ..clear()
        ..addAll(
          (json['snapshots'] as List<dynamic>? ?? const [])
              .whereType<Map>()
              .map(
                (item) =>
                    WorkspaceSnapshot.fromJson(Map<String, dynamic>.from(item)),
              ),
        );
      _notify();
    } catch (_) {
      // A corrupt optional workspace file must not prevent the editor opening.
    }
  }

  Future<void> save() async {
    if (!_persist) {
      return;
    }
    try {
      final file = io.File(_resolvedStoragePath);
      await file.parent.create(recursive: true);
      final temp = io.File('${file.path}.${io.pid}.tmp');
      await temp.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'media_width': mediaWidth,
          'inspector_width': inspectorWidth,
          'timeline_height': timelineHeight,
          'media_on_left': mediaOnLeft,
          'layout_locked': layoutLocked,
          'active_preset': activePreset,
          'custom_presets': customPresets
              .map((preset) => preset.toJson())
              .toList(),
          'assets': assets.map((asset) => asset.toJson()).toList(),
          'snapshots': snapshots.map((snapshot) => snapshot.toJson()).toList(),
        }),
        flush: true,
      );
      if (await file.exists()) {
        await file.delete();
      }
      await temp.rename(file.path);
    } catch (_) {
      // Workspace persistence is best effort and must not interrupt editing.
    }
  }

  String get _resolvedStoragePath {
    if (_storagePath != null) {
      return _storagePath;
    }
    final base =
        io.Platform.environment['APPDATA'] ?? io.Directory.current.path;
    return '$base${io.Platform.pathSeparator}AutoEdit${io.Platform.pathSeparator}workspace.json';
  }

  void _changed() {
    _notify();
    if (!_persist) {
      return;
    }
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 250), () {
      unawaited(save());
    });
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _saveTimer?.cancel();
    unawaited(save());
    super.dispose();
  }
}
