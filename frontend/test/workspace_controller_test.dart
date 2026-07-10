import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_editor_app/state/workspace_controller.dart';

void main() {
  test('workspace presets and panel bounds are applied', () {
    final workspace = WorkspaceController(persist: false);
    workspace.applyPreset(WorkspaceController.presets[2]);
    expect(workspace.activePreset, 'Audio');
    expect(workspace.timelineHeight, 410);
    workspace.setMediaWidth(999);
    workspace.setInspectorWidth(1);
    expect(workspace.mediaWidth, 460);
    expect(workspace.inspectorWidth, 280);
    expect(workspace.snapshots, isNotEmpty);
  });

  test('assets can be tagged and filtered by folder', () {
    final workspace = WorkspaceController(persist: false);
    workspace.addAsset(name: 'interview.mxf', path: r'C:\media\interview.mxf');
    final asset = workspace.assets.single;
    workspace.setAssetFolder(asset, 'Footage');
    workspace.toggleAssetTag(asset, 'Interview');
    workspace.selectAssetFolder('Footage');
    workspace.assetTagFilter = 'Interview';
    expect(workspace.filteredAssets.single.name, 'interview.mxf');
    workspace.assetTagFilter = 'Music';
    expect(workspace.filteredAssets, isEmpty);
  });

  test('history keeps newest snapshots first and caps its size', () {
    final workspace = WorkspaceController(persist: false);
    for (var index = 0; index < 45; index++) {
      workspace.record('Edit $index', 'detail');
    }
    expect(workspace.snapshots, hasLength(40));
    expect(workspace.snapshots.first.label, 'Edit 44');
  });

  test('workspace layout and asset metadata survive a reload', () async {
    final temp = await Directory.systemTemp.createTemp('autoedit_workspace_');
    addTearDown(() => temp.delete(recursive: true));
    final path = '${temp.path}${Platform.pathSeparator}workspace.json';
    final source = WorkspaceController(persist: true, storagePath: path);
    source.applyPreset(WorkspaceController.presets.last);
    source.addAsset(name: 'news.mxf', path: r'C:\media\news.mxf');
    source.setAssetFolder(source.assets.single, 'Footage');
    source.toggleAssetTag(source.assets.single, 'News');
    await source.save();

    final restored = WorkspaceController(persist: false, storagePath: path);
    await restored.load();
    expect(restored.activePreset, 'Review');
    expect(restored.mediaOnLeft, isFalse);
    expect(restored.assets.single.folder, 'Footage');
    expect(restored.assets.single.tags, contains('News'));
    source.dispose();
    restored.dispose();
  });
}
