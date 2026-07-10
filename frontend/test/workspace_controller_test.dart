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

  test('layout lock blocks resizing and custom presets can be managed', () {
    final workspace = WorkspaceController(persist: false);
    workspace.toggleLayoutLock();
    workspace.setMediaWidth(440);
    expect(workspace.mediaWidth, 320);
    workspace.toggleLayoutLock();
    workspace.setMediaWidth(440);
    workspace.saveCurrentPreset('News Desk');
    expect(workspace.customPresets.single.name, 'News Desk');
    expect(workspace.customPresets.single.mediaWidth, 440);
    workspace.deleteCustomPreset(workspace.customPresets.single);
    expect(workspace.customPresets, isEmpty);
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

  test('assets can be searched and filtered by favorite state', () {
    final workspace = WorkspaceController(persist: false);
    workspace.addAsset(name: 'evening_news.mxf', path: r'C:\media\news.mxf');
    workspace.addAsset(name: 'music.wav', path: r'C:\media\music.wav');
    workspace.toggleAssetFavorite(workspace.assets.first);
    workspace.setAssetSearchQuery('evening');
    expect(workspace.filteredAssets.single.name, 'evening_news.mxf');
    workspace.setAssetSearchQuery('');
    workspace.toggleFavoriteAssetsOnly();
    expect(workspace.filteredAssets.single.favorite, isTrue);
  });

  test('offline assets can be relinked without duplicate bin entries', () {
    final workspace = WorkspaceController(persist: false);
    workspace.addAsset(name: 'offline.mxf', path: r'C:\media\offline.mxf');
    workspace.addAsset(name: 'replacement.mxf', path: r'D:\news\online.mxf');
    final offline = workspace.assets.first;

    workspace.relinkAsset(
      offline,
      name: 'online.mxf',
      path: r'D:\news\online.mxf',
    );

    expect(workspace.assets, hasLength(1));
    expect(workspace.assets.single, same(offline));
    expect(workspace.assets.single.name, 'online.mxf');
    expect(workspace.assets.single.path, r'D:\news\online.mxf');
    expect(workspace.snapshots.first.label, 'Asset relinked');
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
    source.toggleAssetFavorite(source.assets.single);
    source.saveCurrentPreset('Broadcast');
    source.setInspectorTab(1);
    source.setWorkspaceView('export');
    source.toggleLayoutLock();
    await source.save();

    final restored = WorkspaceController(persist: false, storagePath: path);
    await restored.load();
    expect(restored.activePreset, 'Broadcast');
    expect(restored.mediaOnLeft, isFalse);
    expect(restored.assets.single.folder, 'Footage');
    expect(restored.assets.single.tags, contains('News'));
    expect(restored.assets.single.favorite, isTrue);
    expect(restored.customPresets.single.name, 'Broadcast');
    expect(restored.activeWorkspaceView, 'export');
    expect(restored.activeInspectorTab, 1);
    expect(restored.layoutLocked, isTrue);
    source.dispose();
    restored.dispose();
  });
}
