import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_editor_app/state/workspace_controller.dart';

void main() {
  test('workspace presets and panel bounds are applied', () {
    final workspace = WorkspaceController();
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
    final workspace = WorkspaceController();
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
    final workspace = WorkspaceController();
    for (var index = 0; index < 45; index++) {
      workspace.record('Edit $index', 'detail');
    }
    expect(workspace.snapshots, hasLength(40));
    expect(workspace.snapshots.first.label, 'Edit 44');
  });
}
