import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:video_player_media_kit/video_player_media_kit.dart';

import 'state/editor_controller.dart';
import 'state/workspace_controller.dart';
import 'widgets/ai_director_panel.dart';
import 'widgets/caption_editor.dart';
import 'widgets/clip_inspector.dart';
import 'widgets/command_palette.dart';
import 'widgets/edit_controls.dart';
import 'widgets/highlight_cards.dart';
import 'widgets/render_outputs_panel.dart';
import 'widgets/status_panel.dart';
import 'widgets/time_format.dart';
import 'widgets/timeline_editor.dart';
import 'widgets/timeline_marker_panel.dart';
import 'widgets/video_preview.dart';
import 'widgets/workspace_tools_panel.dart';

void main() {
  VideoPlayerMediaKit.ensureInitialized(windows: true);
  runApp(
    ChangeNotifierProvider(
      create: (_) => EditorController(enableProjectRecovery: true),
      child: const HighlightEditorApp(),
    ),
  );
}

class HighlightEditorApp extends StatelessWidget {
  const HighlightEditorApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF38BDF8);
    return MaterialApp(
      title: 'AI Highlight Editor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
          primary: seed,
          secondary: const Color(0xFF34D399),
          tertiary: const Color(0xFFF59E0B),
          surface: const Color(0xFF17191F),
          surfaceContainerHighest: const Color(0xFF242832),
          outline: const Color(0xFF343946),
        ),
        scaffoldBackgroundColor: const Color(0xFF0E1014),
        fontFamily: 'Segoe UI',
        visualDensity: VisualDensity.compact,
      ),
      home: const EditorDashboard(),
    );
  }
}

class EditorDashboard extends StatefulWidget {
  const EditorDashboard({super.key, this.workspaceController});

  final WorkspaceController? workspaceController;

  @override
  State<EditorDashboard> createState() => _EditorDashboardState();
}

class _EditorDashboardState extends State<EditorDashboard> {
  final FocusNode _shortcutFocusNode = FocusNode(
    debugLabel: 'AutoEdit shortcuts',
  );
  late final WorkspaceController _workspaceController;
  late final bool _ownsWorkspaceController;

  @override
  void initState() {
    super.initState();
    _ownsWorkspaceController = widget.workspaceController == null;
    _workspaceController = widget.workspaceController ?? WorkspaceController();
  }

  @override
  void dispose() {
    _shortcutFocusNode.dispose();
    if (_ownsWorkspaceController) {
      _workspaceController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<WorkspaceController>.value(
      value: _workspaceController,
      child: Focus(
        focusNode: _shortcutFocusNode,
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
        child: Scaffold(
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final useDesktop =
                    constraints.maxWidth >= 1120 &&
                    constraints.maxHeight >= 680;
                return useDesktop
                    ? const _DesktopEditorShell()
                    : const _CompactEditorShell();
              },
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showCommandPalette() {
    final editor = context.read<EditorController>();
    return showDialog<void>(
      context: context,
      builder: (_) => CommandPalette(
        commands: _buildEditorCommands(editor, _workspaceController),
      ),
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (FocusManager.instance.primaryFocus?.context?.widget is EditableText) {
      return KeyEventResult.ignored;
    }

    final keyboard = HardwareKeyboard.instance;
    final isCtrl = keyboard.isControlPressed || keyboard.isMetaPressed;
    final isShift = keyboard.isShiftPressed;
    final isAlt = keyboard.isAltPressed;
    final key = event.logicalKey;
    final editor = context.read<EditorController>();
    final workspace = _workspaceController;

    bool handled = true;
    if (isCtrl && isShift && !isAlt && key == LogicalKeyboardKey.keyP) {
      unawaited(_showCommandPalette());
    } else if (isCtrl && isShift && !isAlt && key == LogicalKeyboardKey.keyS) {
      unawaited(editor.exportProjectFile());
    } else if (isCtrl && !isShift && !isAlt && key == LogicalKeyboardKey.keyS) {
      unawaited(editor.saveProjectFile());
    } else if (!isCtrl &&
        !isShift &&
        !isAlt &&
        key == LogicalKeyboardKey.backquote) {
      workspace.toggleMaximizeActivePanel();
    } else if (isCtrl && isAlt && !isShift && key == LogicalKeyboardKey.keyW) {
      workspace.toggleLayoutLock();
    } else if (isCtrl && isShift && key == LogicalKeyboardKey.keyZ) {
      editor.redo();
    } else if (isCtrl && isShift && !isAlt && key == LogicalKeyboardKey.keyA) {
      editor.clearSegmentSelection();
    } else if (!isCtrl &&
        !isAlt &&
        !isShift &&
        key == LogicalKeyboardKey.escape) {
      editor.clearSegmentSelection();
    } else if (!isCtrl &&
        !isAlt &&
        !isShift &&
        key == LogicalKeyboardKey.minus) {
      editor.zoomTimeline(-0.5);
    } else if (!isCtrl &&
        !isAlt &&
        !isShift &&
        key == LogicalKeyboardKey.equal) {
      editor.zoomTimeline(0.5);
    } else if (!isCtrl &&
        !isAlt &&
        !isShift &&
        key == LogicalKeyboardKey.backslash) {
      editor.fitTimelineZoom();
    } else if (isAlt &&
        !isCtrl &&
        !isShift &&
        key == LogicalKeyboardKey.minus) {
      editor.adjustTimelineTrackHeight(-1);
    } else if (isAlt &&
        !isCtrl &&
        !isShift &&
        key == LogicalKeyboardKey.equal) {
      editor.adjustTimelineTrackHeight(1);
    } else if (isCtrl &&
        !isShift &&
        !isAlt &&
        key == LogicalKeyboardKey.digit1) {
      editor.toggleVideoTrackTarget();
    } else if (isCtrl &&
        !isShift &&
        !isAlt &&
        key == LogicalKeyboardKey.digit2) {
      editor.toggleAudioTrack1Target();
    } else if (isCtrl &&
        !isShift &&
        !isAlt &&
        key == LogicalKeyboardKey.digit3) {
      editor.toggleAudioTrack2Target();
    } else if (isCtrl &&
        isAlt &&
        !isShift &&
        key == LogicalKeyboardKey.digit1) {
      editor.toggleVideoTrackLock();
    } else if (isCtrl &&
        isAlt &&
        !isShift &&
        key == LogicalKeyboardKey.digit2) {
      editor.toggleAudioTrack1Lock();
    } else if (isCtrl &&
        isAlt &&
        !isShift &&
        key == LogicalKeyboardKey.digit3) {
      editor.toggleAudioTrack2Lock();
    } else if (isCtrl && !isShift && key == LogicalKeyboardKey.keyZ) {
      editor.undo();
    } else if (isCtrl && isShift && key == LogicalKeyboardKey.keyK) {
      editor.addEditToAllTracksAtPlayhead();
    } else if (isCtrl && !isShift && key == LogicalKeyboardKey.keyK) {
      editor.addEditAtPlayhead();
    } else if (isCtrl && !isShift && key == LogicalKeyboardKey.keyL) {
      editor.toggleSelectedAudioLink();
    } else if (isCtrl && isShift && key == LogicalKeyboardKey.keyD) {
      editor.applyDefaultAudioTransition();
    } else if (isCtrl && !isShift && key == LogicalKeyboardKey.keyD) {
      editor.applyDefaultVideoTransition();
    } else if (isCtrl && !isShift && !isAlt && key == LogicalKeyboardKey.keyC) {
      editor.copySelectedSegment();
    } else if (isCtrl && !isShift && !isAlt && key == LogicalKeyboardKey.keyX) {
      editor.cutSelectedSegment();
    } else if (isCtrl && !isShift && !isAlt && key == LogicalKeyboardKey.keyV) {
      editor.pasteClipboardSegment();
    } else if (isCtrl && isShift && key == LogicalKeyboardKey.keyX) {
      editor.clearMarks();
    } else if (isCtrl &&
        !isAlt &&
        !isShift &&
        key == LogicalKeyboardKey.semicolon) {
      editor.liftSelectedSegment();
    } else if (isCtrl &&
        !isAlt &&
        !isShift &&
        key == LogicalKeyboardKey.quote) {
      editor.extractSelectedSegment();
    } else if (isCtrl && isAlt && key == LogicalKeyboardKey.keyM) {
      editor.clearTimelineMarkers();
    } else if (isCtrl && isShift && key == LogicalKeyboardKey.keyM) {
      editor.jumpToPreviousTimelineMarker();
    } else if (isCtrl && isShift && key == LogicalKeyboardKey.keyI) {
      editor.clearMarkIn();
    } else if (isCtrl && isShift && key == LogicalKeyboardKey.keyO) {
      editor.clearMarkOut();
    } else if (!isCtrl && !isAlt && isShift && key == LogicalKeyboardKey.keyI) {
      unawaited(editor.jumpToMarkIn());
    } else if (!isCtrl && !isAlt && isShift && key == LogicalKeyboardKey.keyO) {
      unawaited(editor.jumpToMarkOut());
    } else if (!isCtrl && !isAlt && isShift && key == LogicalKeyboardKey.home) {
      unawaited(editor.jumpToSelectedClipStart());
    } else if (!isCtrl && !isAlt && isShift && key == LogicalKeyboardKey.end) {
      unawaited(editor.jumpToSelectedClipEnd());
    } else if (!isCtrl &&
        !isAlt &&
        !isShift &&
        key == LogicalKeyboardKey.home) {
      unawaited(editor.jumpToTimelineStart());
    } else if (!isCtrl && !isAlt && !isShift && key == LogicalKeyboardKey.end) {
      unawaited(editor.jumpToTimelineEnd());
    } else if (!isCtrl &&
        !isAlt &&
        !isShift &&
        (key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.pageUp)) {
      unawaited(editor.jumpToPreviousEditPoint());
    } else if (!isCtrl &&
        !isAlt &&
        !isShift &&
        (key == LogicalKeyboardKey.arrowDown ||
            key == LogicalKeyboardKey.pageDown)) {
      unawaited(editor.jumpToNextEditPoint());
    } else if (!isCtrl &&
        !isAlt &&
        !isShift &&
        key == LogicalKeyboardKey.arrowLeft) {
      unawaited(editor.stepPlayheadByFrames(-1));
    } else if (!isCtrl &&
        !isAlt &&
        !isShift &&
        key == LogicalKeyboardKey.arrowRight) {
      unawaited(editor.stepPlayheadByFrames(1));
    } else if (!isCtrl &&
        !isAlt &&
        isShift &&
        key == LogicalKeyboardKey.arrowLeft) {
      unawaited(editor.stepPlayheadByFrames(-10));
    } else if (!isCtrl &&
        !isAlt &&
        isShift &&
        key == LogicalKeyboardKey.arrowRight) {
      unawaited(editor.stepPlayheadByFrames(10));
    } else if (!isCtrl &&
        isAlt &&
        !isShift &&
        key == LogicalKeyboardKey.arrowLeft) {
      editor.slipSelectedSegmentFrames(-1);
    } else if (!isCtrl &&
        isAlt &&
        !isShift &&
        key == LogicalKeyboardKey.arrowRight) {
      editor.slipSelectedSegmentFrames(1);
    } else if (!isCtrl &&
        isAlt &&
        isShift &&
        key == LogicalKeyboardKey.arrowLeft) {
      editor.slipSelectedSegmentFrames(-10);
    } else if (!isCtrl &&
        isAlt &&
        isShift &&
        key == LogicalKeyboardKey.arrowRight) {
      editor.slipSelectedSegmentFrames(10);
    } else if (isCtrl &&
        !isAlt &&
        !isShift &&
        key == LogicalKeyboardKey.arrowLeft) {
      editor.selectPreviousSegment();
    } else if (isCtrl &&
        !isAlt &&
        !isShift &&
        key == LogicalKeyboardKey.arrowRight) {
      editor.selectNextSegment();
    } else if (isCtrl &&
        !isAlt &&
        !isShift &&
        key == LogicalKeyboardKey.arrowUp) {
      editor.moveSelectedSegment(-1);
    } else if (isCtrl &&
        !isAlt &&
        !isShift &&
        key == LogicalKeyboardKey.arrowDown) {
      editor.moveSelectedSegment(1);
    } else if (!isCtrl &&
        isAlt &&
        !isShift &&
        key == LogicalKeyboardKey.comma) {
      editor.rollSelectedIncomingEditFrames(-1);
    } else if (!isCtrl &&
        isAlt &&
        !isShift &&
        key == LogicalKeyboardKey.period) {
      editor.rollSelectedIncomingEditFrames(1);
    } else if (!isCtrl && isAlt && isShift && key == LogicalKeyboardKey.comma) {
      editor.rollSelectedOutgoingEditFrames(-1);
    } else if (!isCtrl &&
        isAlt &&
        isShift &&
        key == LogicalKeyboardKey.period) {
      editor.rollSelectedOutgoingEditFrames(1);
    } else if (isCtrl &&
        isAlt &&
        !isShift &&
        key == LogicalKeyboardKey.arrowLeft) {
      editor.nudgeSelectedAudioFrames(-1);
    } else if (isCtrl &&
        isAlt &&
        !isShift &&
        key == LogicalKeyboardKey.arrowRight) {
      editor.nudgeSelectedAudioFrames(1);
    } else if (isCtrl &&
        isAlt &&
        isShift &&
        key == LogicalKeyboardKey.arrowLeft) {
      editor.nudgeSelectedAudioFrames(-10);
    } else if (isCtrl &&
        isAlt &&
        isShift &&
        key == LogicalKeyboardKey.arrowRight) {
      editor.nudgeSelectedAudioFrames(10);
    } else if (!isCtrl &&
        !isAlt &&
        !isShift &&
        key == LogicalKeyboardKey.keyJ) {
      unawaited(editor.shuttleReverse());
    } else if (!isCtrl &&
        !isAlt &&
        !isShift &&
        key == LogicalKeyboardKey.keyK) {
      unawaited(editor.shuttlePause());
    } else if (!isCtrl &&
        !isAlt &&
        !isShift &&
        key == LogicalKeyboardKey.keyL) {
      unawaited(editor.shuttleForward());
    } else if (!isCtrl &&
        !isAlt &&
        !isShift &&
        key == LogicalKeyboardKey.keyC) {
      editor.setRazorTool();
    } else if (!isCtrl &&
        !isAlt &&
        !isShift &&
        key == LogicalKeyboardKey.keyD) {
      editor.selectSegmentAtPlayhead();
    } else if (!isCtrl &&
        !isAlt &&
        !isShift &&
        key == LogicalKeyboardKey.keyR) {
      editor.rateStretchSelectedToMarks();
    } else if (!isCtrl &&
        !isAlt &&
        !isShift &&
        key == LogicalKeyboardKey.keyV) {
      editor.setSelectionTool();
    } else if (!isCtrl &&
        !isAlt &&
        !isShift &&
        key == LogicalKeyboardKey.keyS) {
      editor.toggleTimelineSnapping();
    } else if (!isCtrl && !isAlt && isShift && key == LogicalKeyboardKey.keyE) {
      editor.toggleSelectedClipEnabled();
    } else if (!isCtrl &&
        !isAlt &&
        !isShift &&
        key == LogicalKeyboardKey.keyI) {
      editor.setMarkInFromPlayhead();
    } else if (!isCtrl &&
        !isAlt &&
        !isShift &&
        key == LogicalKeyboardKey.keyO) {
      editor.setMarkOutFromPlayhead();
    } else if (!isCtrl && !isAlt && isShift && key == LogicalKeyboardKey.keyM) {
      editor.jumpToNextTimelineMarker();
    } else if (!isCtrl &&
        !isAlt &&
        !isShift &&
        key == LogicalKeyboardKey.keyM) {
      editor.addTimelineMarkerAtPlayhead();
    } else if (!isCtrl &&
        !isAlt &&
        !isShift &&
        key == LogicalKeyboardKey.keyX) {
      editor.markSelectedClip();
    } else if (!isCtrl &&
        !isAlt &&
        !isShift &&
        key == LogicalKeyboardKey.comma) {
      editor.insertMarkedSegmentAtSelection();
    } else if (!isCtrl &&
        !isAlt &&
        !isShift &&
        key == LogicalKeyboardKey.period) {
      editor.overwriteSelectedSegmentWithMarks();
    } else if (!isCtrl &&
        !isAlt &&
        !isShift &&
        key == LogicalKeyboardKey.semicolon) {
      editor.liftMarkedRange();
    } else if (!isCtrl &&
        !isAlt &&
        !isShift &&
        key == LogicalKeyboardKey.quote) {
      editor.extractMarkedRange();
    } else if (!isCtrl && !isAlt && isShift && key == LogicalKeyboardKey.keyQ) {
      editor.extendSelectedStartToPlayhead();
    } else if (!isCtrl && !isAlt && isShift && key == LogicalKeyboardKey.keyW) {
      editor.extendSelectedEndToPlayhead();
    } else if (!isCtrl &&
        !isAlt &&
        !isShift &&
        key == LogicalKeyboardKey.keyQ) {
      editor.rippleTrimSelectedStartToPlayhead();
    } else if (!isCtrl &&
        !isAlt &&
        !isShift &&
        key == LogicalKeyboardKey.keyW) {
      editor.rippleTrimSelectedEndToPlayhead();
    } else if (!isCtrl &&
        !isAlt &&
        isShift &&
        (key == LogicalKeyboardKey.delete ||
            key == LogicalKeyboardKey.backspace)) {
      editor.extractSelectedSegment();
    } else if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      editor.deleteSelectedSegment();
    } else if (!isCtrl &&
        !isAlt &&
        !isShift &&
        key == LogicalKeyboardKey.space) {
      editor.togglePlayback();
    } else {
      handled = false;
    }

    return handled ? KeyEventResult.handled : KeyEventResult.ignored;
  }
}

Future<void> _showEditorCommandPalette(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => CommandPalette(
      commands: _buildEditorCommands(
        context.read<EditorController>(),
        context.read<WorkspaceController>(),
      ),
    ),
  );
}

List<EditorCommand> _buildEditorCommands(
  EditorController editor,
  WorkspaceController workspace,
) {
  return [
    EditorCommand(
      label: 'Import media',
      category: 'File',
      icon: Icons.video_file_outlined,
      action: editor.pickVideo,
      keywords: const ['open', 'mxf', 'video'],
    ),
    EditorCommand(
      label: 'Save project',
      category: 'File',
      icon: Icons.save_outlined,
      action: editor.saveProjectFile,
      shortcut: 'Ctrl+S',
      enabled: editor.canSaveProjectFile,
      keywords: const ['project', 'save'],
    ),
    EditorCommand(
      label: 'Save project as',
      category: 'File',
      icon: Icons.save_as_outlined,
      action: editor.exportProjectFile,
      shortcut: 'Ctrl+Shift+S',
      enabled: editor.canSaveProjectFile,
      keywords: const ['project', 'save as'],
    ),
    EditorCommand(
      label: 'Open project',
      category: 'File',
      icon: Icons.folder_open,
      action: editor.importProjectFile,
      keywords: const ['project', 'open'],
    ),
    EditorCommand(
      label: 'Analyze selected media',
      category: 'AI',
      icon: Icons.auto_awesome,
      action: editor.startUpload,
      enabled: editor.canStartUpload,
      keywords: const ['transcribe', 'highlight', 'whisper'],
    ),
    EditorCommand(
      label: 'Undo last edit',
      category: 'Edit',
      icon: Icons.undo,
      action: editor.undo,
      shortcut: 'Ctrl+Z',
      enabled: editor.canUndo,
    ),
    EditorCommand(
      label: 'Redo edit',
      category: 'Edit',
      icon: Icons.redo,
      action: editor.redo,
      shortcut: 'Ctrl+Shift+Z',
      enabled: editor.canRedo,
    ),
    EditorCommand(
      label: 'Add edit at playhead',
      category: 'Timeline',
      icon: Icons.content_cut,
      action: editor.addEditAtPlayhead,
      shortcut: 'Ctrl+K',
      enabled: editor.hasTimeline,
      keywords: const ['split', 'razor', 'cut'],
    ),
    EditorCommand(
      label: 'Add marker at playhead',
      category: 'Timeline',
      icon: Icons.bookmark_add_outlined,
      action: editor.addTimelineMarkerAtPlayhead,
      shortcut: 'M',
      enabled: editor.hasTimelineSource,
    ),
    EditorCommand(
      label: editor.timelineSnappingEnabled
          ? 'Disable timeline snapping'
          : 'Enable timeline snapping',
      category: 'Timeline',
      icon: Icons.vertical_align_center,
      action: editor.toggleTimelineSnapping,
      shortcut: 'S',
    ),
    EditorCommand(
      label: workspace.maximizedPanel == null
          ? 'Maximize active panel'
          : 'Restore panel layout',
      category: 'Workspace',
      icon: workspace.maximizedPanel == null
          ? Icons.fullscreen
          : Icons.fullscreen_exit,
      action: workspace.toggleMaximizeActivePanel,
      shortcut: '`',
      keywords: const ['focus', 'panel'],
    ),
    EditorCommand(
      label: workspace.layoutLocked
          ? 'Unlock workspace layout'
          : 'Lock workspace layout',
      category: 'Workspace',
      icon: workspace.layoutLocked ? Icons.lock_open : Icons.lock_outline,
      action: workspace.toggleLayoutLock,
      shortcut: 'Ctrl+Alt+W',
    ),
    EditorCommand(
      label: 'Apply Edit workspace',
      category: 'Workspace',
      icon: Icons.space_dashboard_outlined,
      action: () => workspace.applyPreset(WorkspaceController.presets.first),
      keywords: const ['reset', 'layout'],
    ),
    EditorCommand(
      label: 'Render current timeline',
      category: 'Export',
      icon: Icons.movie_creation_outlined,
      action: editor.requestRender,
      enabled: editor.canRender,
      keywords: const ['export', 'youtube'],
    ),
  ];
}

class _DesktopEditorShell extends StatelessWidget {
  const _DesktopEditorShell();

  @override
  Widget build(BuildContext context) {
    final workspace = context.watch<WorkspaceController>();
    final mediaPanel = SizedBox(
      width: workspace.mediaWidth,
      child: const _WorkspacePanelFocus(panel: 'media', child: _MediaPanel()),
    );
    final inspectorPanel = SizedBox(
      width: workspace.inspectorWidth,
      child: const _WorkspacePanelFocus(
        panel: 'inspector',
        child: _InspectorPanel(),
      ),
    );
    final mediaHandle = _PanelResizeHandle(
      key: const Key('workspace-media-resize'),
      axis: Axis.vertical,
      enabled: !workspace.layoutLocked,
      onDragUpdate: (delta) => workspace.setMediaWidth(
        workspace.mediaWidth + (workspace.mediaOnLeft ? delta : -delta),
      ),
      onDragEnd: () =>
          workspace.finishPanelResize('Media panel', workspace.mediaWidth),
    );
    final inspectorHandle = _PanelResizeHandle(
      key: const Key('workspace-inspector-resize'),
      axis: Axis.vertical,
      enabled: !workspace.layoutLocked,
      onDragUpdate: (delta) => workspace.setInspectorWidth(
        workspace.inspectorWidth + (workspace.mediaOnLeft ? -delta : delta),
      ),
      onDragEnd: () => workspace.finishPanelResize(
        'Inspector panel',
        workspace.inspectorWidth,
      ),
    );
    final maximizedPanel = workspace.maximizedPanel;
    if (maximizedPanel != null) {
      final panel = switch (maximizedPanel) {
        'media' => const _MediaPanel(),
        'inspector' => const _InspectorPanel(),
        'timeline' => const _TimelinePanel(),
        _ => const _PreviewStage(),
      };
      return Column(
        children: [
          const _TopBar(),
          const _CommandBar(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: _WorkspacePanelFocus(panel: maximizedPanel, child: panel),
            ),
          ),
        ],
      );
    }
    return Column(
      children: [
        const _TopBar(),
        const _CommandBar(),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 56, child: _WorkspaceRail()),
              _VerticalRule(),
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: workspace.mediaOnLeft
                            ? [
                                mediaPanel,
                                mediaHandle,
                                const Expanded(
                                  child: _WorkspacePanelFocus(
                                    panel: 'preview',
                                    child: _PreviewStage(),
                                  ),
                                ),
                                inspectorHandle,
                                inspectorPanel,
                              ]
                            : [
                                inspectorPanel,
                                inspectorHandle,
                                const Expanded(
                                  child: _WorkspacePanelFocus(
                                    panel: 'preview',
                                    child: _PreviewStage(),
                                  ),
                                ),
                                mediaHandle,
                                mediaPanel,
                              ],
                      ),
                    ),
                    _PanelResizeHandle(
                      key: const Key('workspace-timeline-resize'),
                      axis: Axis.horizontal,
                      enabled: !workspace.layoutLocked,
                      onDragUpdate: (delta) => workspace.setTimelineHeight(
                        workspace.timelineHeight - delta,
                      ),
                      onDragEnd: () => workspace.finishPanelResize(
                        'Timeline',
                        workspace.timelineHeight,
                      ),
                    ),
                    SizedBox(
                      height: workspace.timelineHeight,
                      child: const _WorkspacePanelFocus(
                        panel: 'timeline',
                        child: _TimelinePanel(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PanelResizeHandle extends StatelessWidget {
  const _PanelResizeHandle({
    super.key,
    required this.axis,
    required this.onDragUpdate,
    required this.onDragEnd,
    this.enabled = true,
  });

  final Axis axis;
  final ValueChanged<double> onDragUpdate;
  final VoidCallback onDragEnd;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final vertical = axis == Axis.vertical;
    return MouseRegion(
      cursor: enabled
          ? (vertical
                ? SystemMouseCursors.resizeColumn
                : SystemMouseCursors.resizeRow)
          : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: enabled && vertical
            ? (details) => onDragUpdate(details.delta.dx)
            : null,
        onHorizontalDragEnd: enabled && vertical ? (_) => onDragEnd() : null,
        onVerticalDragUpdate: !enabled || vertical
            ? null
            : (details) => onDragUpdate(details.delta.dy),
        onVerticalDragEnd: enabled && !vertical ? (_) => onDragEnd() : null,
        child: SizedBox(
          width: vertical ? 6 : double.infinity,
          height: vertical ? double.infinity : 6,
          child: ColoredBox(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }
}

class _WorkspacePanelFocus extends StatelessWidget {
  const _WorkspacePanelFocus({required this.panel, required this.child});

  final String panel;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final workspace = context.watch<WorkspaceController>();
    final active = workspace.activePanel == panel;
    return MouseRegion(
      onEnter: (_) => context.read<WorkspaceController>().setActivePanel(panel),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapDown: (_) =>
            context.read<WorkspaceController>().setActivePanel(panel),
        onSecondaryTapDown: panel == 'timeline'
            ? null
            : (details) => _showPanelMenu(context, details.globalPosition),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
              color: active
                  ? Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.65)
                  : Colors.transparent,
            ),
          ),
          child: child,
        ),
      ),
    );
  }

  Future<void> _showPanelMenu(BuildContext context, Offset position) async {
    final workspace = context.read<WorkspaceController>();
    workspace.setActivePanel(panel);
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        PopupMenuItem(
          value: 'maximize',
          child: ListTile(
            dense: true,
            leading: Icon(
              workspace.maximizedPanel == null
                  ? Icons.fullscreen
                  : Icons.fullscreen_exit,
            ),
            title: Text(
              workspace.maximizedPanel == null
                  ? 'Maximize panel  (`)'
                  : 'Restore panel layout  (`)',
            ),
          ),
        ),
        PopupMenuItem(
          value: 'lock',
          child: ListTile(
            dense: true,
            leading: Icon(
              workspace.layoutLocked ? Icons.lock_open : Icons.lock_outline,
            ),
            title: Text(
              workspace.layoutLocked ? 'Unlock layout' : 'Lock layout',
            ),
          ),
        ),
        PopupMenuItem(
          value: 'swap',
          enabled: !workspace.layoutLocked,
          child: const ListTile(
            dense: true,
            leading: Icon(Icons.swap_horiz),
            title: Text('Swap side panels'),
          ),
        ),
      ],
    );
    switch (action) {
      case 'maximize':
        workspace.toggleMaximizeActivePanel();
        break;
      case 'lock':
        workspace.toggleLayoutLock();
        break;
      case 'swap':
        workspace.swapSidePanels();
        break;
    }
  }
}

class _CompactEditorShell extends StatelessWidget {
  const _CompactEditorShell();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _TopBar(compact: true),
        const _CommandBar(compact: true),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(14),
            children: [
              const _EngineStatus(),
              const SizedBox(height: 12),
              const StatusPanel(),
              const SizedBox(height: 12),
              const SizedBox(height: 300, child: _PreviewStage()),
              const SizedBox(height: 12),
              const _TimelinePanel(compact: true),
              const SizedBox(height: 12),
              SizedBox(height: 360, child: const _InspectorPanel()),
            ],
          ),
        ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<EditorController>();
    return Container(
      height: compact ? 56 : 58,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF121419),
        border: Border(
          bottom: BorderSide(color: Theme.of(context).colorScheme.outline),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(7),
            ),
            child: const Icon(
              Icons.auto_awesome_motion,
              size: 19,
              color: Colors.black,
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: compact ? 140 : 230,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AutoEdit',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                Tooltip(
                  message:
                      controller.projectFilePath ?? controller.projectFileLabel,
                  child: Text(
                    controller.projectTitleLabel,
                    key: const Key('project-title-label'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: controller.hasUnsavedProjectChanges
                          ? Theme.of(context).colorScheme.tertiary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (!compact) ...[
            const _WorkspaceTab(label: 'Edit', selected: true),
            const _WorkspaceTab(label: 'Captions'),
            const _WorkspaceTab(label: 'Export'),
            const SizedBox(width: 10),
            IconButton.outlined(
              tooltip: 'Workspace, assets, history',
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => Dialog(
                  child: SizedBox(
                    width: 460,
                    height: 620,
                    child: const WorkspaceToolsPanel(),
                  ),
                ),
              ),
              icon: const Icon(Icons.dashboard_customize_outlined),
            ),
            const SizedBox(width: 6),
            IconButton.outlined(
              tooltip: 'Command palette (Ctrl+Shift+P)',
              onPressed: () => _showEditorCommandPalette(context),
              icon: const Icon(Icons.search),
            ),
            const SizedBox(width: 6),
            IconButton.outlined(
              tooltip: '되돌리기',
              onPressed: controller.canUndo
                  ? context.read<EditorController>().undo
                  : null,
              icon: const Icon(Icons.undo),
            ),
            const SizedBox(width: 6),
            IconButton.outlined(
              tooltip: '다시 실행',
              onPressed: controller.canRedo
                  ? context.read<EditorController>().redo
                  : null,
              icon: const Icon(Icons.redo),
            ),
          ],
          const Spacer(),
          if (!compact) ...[
            _EnginePill(stateText: controller.engineState.message),
            const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }
}

class _CommandBar extends StatelessWidget {
  const _CommandBar({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<EditorController>();
    final editor = context.read<EditorController>();
    final selected = controller.selectedSegment;
    final canUseMarks = controller.hasValidMarks;
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      height: compact ? 54 : 50,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF101217),
        border: Border(bottom: BorderSide(color: colorScheme.outline)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _ToolbarButton(
              icon: Icons.add_to_photos_outlined,
              label: 'Import',
              onPressed: controller.isUploading ? null : editor.pickVideo,
            ),
            _ToolbarButton(
              icon: Icons.auto_awesome,
              label: 'Analyze',
              onPressed: controller.canStartUpload ? editor.startUpload : null,
            ),
            const _ToolbarDivider(),
            IconButton.outlined(
              tooltip: '되돌리기',
              onPressed: controller.canUndo ? editor.undo : null,
              icon: const Icon(Icons.undo),
            ),
            const SizedBox(width: 6),
            IconButton.outlined(
              tooltip: '다시 실행',
              onPressed: controller.canRedo ? editor.redo : null,
              icon: const Icon(Icons.redo),
            ),
            const _ToolbarDivider(),
            _ToolbarButton(
              icon: Icons.save_outlined,
              label: 'Save',
              onPressed: controller.canSaveProjectFile
                  ? editor.saveProjectFile
                  : null,
            ),
            _ToolbarButton(
              icon: Icons.save_as_outlined,
              label: 'Save As',
              onPressed: controller.canSaveProjectFile
                  ? editor.exportProjectFile
                  : null,
            ),
            _ToolbarButton(
              icon: Icons.folder_open,
              label: 'Open',
              onPressed: editor.importProjectFile,
            ),
            _ToolbarButton(
              icon: Icons.restore,
              label: 'Recover',
              onPressed: controller.hasRecoverySnapshot
                  ? editor.restoreRecoveryProject
                  : null,
            ),
            const _ToolbarDivider(),
            _ToolbarButton(
              icon: Icons.start,
              label: 'In',
              onPressed: controller.hasTimeline
                  ? editor.setMarkInFromPlayhead
                  : null,
            ),
            _ToolbarButton(
              icon: Icons.flag_outlined,
              label: 'Out',
              onPressed: controller.hasTimeline
                  ? editor.setMarkOutFromPlayhead
                  : null,
            ),
            _ToolbarButton(
              icon: Icons.add_box_outlined,
              label: 'Add',
              onPressed: canUseMarks ? editor.addMarkedSegment : null,
            ),
            _ToolbarButton(
              icon: Icons.swap_horiz,
              label: 'Apply',
              onPressed: selected != null && canUseMarks
                  ? editor.applyMarksToSelectedSegment
                  : null,
            ),
            _ToolbarButton(
              icon: Icons.vertical_align_center,
              label: 'Lift',
              onPressed: controller.canLiftOrExtractMarkedRange
                  ? editor.liftMarkedRange
                  : null,
            ),
            _ToolbarButton(
              icon: Icons.playlist_remove,
              label: 'Extract',
              onPressed: controller.canLiftOrExtractMarkedRange
                  ? editor.extractMarkedRange
                  : null,
            ),
            _ToolbarButton(
              icon: Icons.call_split,
              label: 'Split',
              onPressed: selected == null
                  ? null
                  : editor.splitSelectedAtPlayhead,
            ),
            _ToolbarButton(
              icon: Icons.clear,
              label: 'Clear',
              onPressed: controller.markIn != null || controller.markOut != null
                  ? editor.clearMarks
                  : null,
            ),
            _ToolbarButton(
              icon: Icons.bookmark_add_outlined,
              label: 'Marker',
              onPressed: controller.timelineSourceDuration > 0
                  ? editor.addTimelineMarkerAtPlayhead
                  : null,
            ),
            IconButton.outlined(
              tooltip: '이전 마커로 이동',
              onPressed: controller.canJumpToPreviousTimelineMarker
                  ? editor.jumpToPreviousTimelineMarker
                  : null,
              icon: const Icon(Icons.skip_previous),
            ),
            const SizedBox(width: 6),
            IconButton.outlined(
              tooltip: '다음 마커로 이동',
              onPressed: controller.canJumpToNextTimelineMarker
                  ? editor.jumpToNextTimelineMarker
                  : null,
              icon: const Icon(Icons.skip_next),
            ),
            const SizedBox(width: 6),
            _ToolbarButton(
              icon: Icons.bookmark_remove_outlined,
              label: 'Clear M',
              onPressed: controller.hasTimelineMarkers
                  ? editor.clearTimelineMarkers
                  : null,
            ),
            const _ToolbarDivider(),
            IconButton.outlined(
              tooltip: '타임라인 축소 (-)',
              onPressed: controller.hasTimeline
                  ? () => editor.zoomTimeline(-0.5)
                  : null,
              icon: const Icon(Icons.zoom_out),
            ),
            const SizedBox(width: 6),
            IconButton.outlined(
              tooltip: '타임라인 확대 (=)',
              onPressed: controller.hasTimeline
                  ? () => editor.zoomTimeline(0.5)
                  : null,
              icon: const Icon(Icons.zoom_in),
            ),
            const SizedBox(width: 6),
            IconButton.outlined(
              tooltip: '타임라인 전체 보기 (\\)',
              onPressed: controller.hasTimeline ? editor.fitTimelineZoom : null,
              icon: const Icon(Icons.zoom_out_map),
            ),
            const SizedBox(width: 6),
            FilterChip(
              selected: controller.timelineTrackHeightScale > 1.05,
              onSelected: controller.hasTimelineSource
                  ? (_) => editor.cycleTimelineTrackHeight()
                  : null,
              avatar: const Icon(Icons.height, size: 18),
              label: Text(controller.timelineTrackHeightLabel),
              tooltip: '트랙 높이 전환 (Alt+- / Alt+=)',
            ),
            const SizedBox(width: 10),
            SegmentedButton<String>(
              multiSelectionEnabled: true,
              segments: const [
                ButtonSegment(value: '16:9', label: Text('16:9')),
                ButtonSegment(value: '9:16', label: Text('9:16')),
                ButtonSegment(value: '1:1', label: Text('1:1')),
              ],
              selected: controller.selectedExportProfileSet,
              onSelectionChanged: controller.hasTimeline
                  ? editor.setExportProfiles
                  : null,
            ),
            const SizedBox(width: 8),
            FilterChip(
              selected: controller.includeCaptions,
              onSelected: controller.hasTimeline
                  ? editor.setIncludeCaptions
                  : null,
              avatar: const Icon(Icons.closed_caption_outlined, size: 18),
              label: const Text('Captions'),
            ),
            const _ToolbarDivider(),
            FilledButton.icon(
              onPressed: controller.canRender ? editor.requestRender : null,
              icon: const Icon(Icons.file_upload_outlined),
              label: Text(
                controller.hasMultiFormatExport
                    ? 'Export All'
                    : controller.renderUrl == null
                    ? 'Export'
                    : 'Re-export',
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: controller.canRender
                  ? editor.requestShortsRender
                  : null,
              icon: const Icon(Icons.phone_iphone),
              label: const Text('Shorts'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
        ),
      ),
    );
  }
}

class _ToolbarDivider extends StatelessWidget {
  const _ToolbarDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 30,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: Theme.of(context).colorScheme.outline,
    );
  }
}

class _MediaPanel extends StatelessWidget {
  const _MediaPanel();

  static const _baseFolders = [
    'All',
    'Unsorted',
    'Footage',
    'Audio',
    'Graphics',
  ];

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<EditorController>();
    final workspace = context.watch<WorkspaceController>();
    final selectedFile = controller.selectedFile;
    final selectedPath = selectedFile?.path;
    if (selectedFile != null &&
        selectedPath != null &&
        selectedPath.isNotEmpty &&
        !workspace.assets.any((asset) => asset.path == selectedPath)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        workspace.addAsset(name: selectedFile.name, path: selectedPath);
      });
    }
    final folders = [
      ..._baseFolders,
      for (final folder
          in workspace.assets.map((asset) => asset.folder).toSet())
        if (!_baseFolders.contains(folder)) folder,
    ];
    final visibleAssets = workspace.filteredAssets;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: _PanelHeader(
                  title: 'Project Media',
                  icon: Icons.perm_media_outlined,
                ),
              ),
              IconButton.outlined(
                key: const Key('media-bin-import'),
                tooltip: 'Import media to bin',
                onPressed: controller.isUploading
                    ? null
                    : () => _importAssets(context),
                icon: const Icon(Icons.add, size: 19),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('media-bin-search'),
            onChanged: workspace.setAssetSearchQuery,
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 19),
              hintText: 'Search media',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: const Key('media-bin-folder'),
                  initialValue: folders.contains(workspace.assetFolder)
                      ? workspace.assetFolder
                      : 'All',
                  isExpanded: true,
                  isDense: true,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.folder_outlined, size: 18),
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final folder in folders)
                      DropdownMenuItem(value: folder, child: Text(folder)),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      workspace.selectAssetFolder(value);
                    }
                  },
                ),
              ),
              const SizedBox(width: 6),
              IconButton.outlined(
                key: const Key('media-bin-favorites'),
                tooltip: 'Favorites only',
                isSelected: workspace.favoriteAssetsOnly,
                onPressed: workspace.toggleFavoriteAssetsOnly,
                icon: Icon(
                  workspace.favoriteAssetsOnly ? Icons.star : Icons.star_border,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 7, bottom: 5),
            child: Text(
              '${visibleAssets.length} of ${workspace.assets.length} items',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: visibleAssets.isEmpty
                ? _MediaBinEmpty(onImport: () => _importAssets(context))
                : ListView.builder(
                    key: const Key('media-bin-list'),
                    itemCount: visibleAssets.length,
                    itemBuilder: (context, index) {
                      final asset = visibleAssets[index];
                      final active = controller.sourceMediaPath == asset.path;
                      return _MediaAssetTile(
                        asset: asset,
                        active: active,
                        onOpen: asset.isOffline
                            ? null
                            : () =>
                                  _activateMediaAssetPath(context, asset.path),
                        onFavorite: () => workspace.toggleAssetFavorite(asset),
                        onRelink: asset.isOffline
                            ? () => _relinkAsset(context, asset, active: active)
                            : null,
                        onSecondaryTap: (position) => _showAssetMenu(
                          context,
                          asset,
                          position,
                          active: active,
                        ),
                      );
                    },
                  ),
          ),
          if (controller.isUploading ||
              controller.isProbingMedia ||
              controller.isPreparingPreview ||
              controller.job?.status == 'processing' ||
              controller.errorMessage != null) ...[
            const SizedBox(height: 7),
            _MediaActivityStrip(controller: controller),
          ],
        ],
      ),
    );
  }

  Future<void> _importAssets(BuildContext context) async {
    final editor = context.read<EditorController>();
    final workspace = context.read<WorkspaceController>();
    final files = await editor.pickMediaAssets();
    if (!context.mounted || files.isEmpty) {
      return;
    }
    for (final file in files) {
      final path = file.path;
      if (path != null && path.isNotEmpty) {
        workspace.addAsset(name: file.name, path: path);
      }
    }
    if (editor.selectedFile == null) {
      final first = files.first;
      final path = first.path;
      if (path != null && path.isNotEmpty) {
        await editor.openMediaFile(first);
      }
    }
  }

  Future<void> _showAssetMenu(
    BuildContext context,
    AssetEntry asset,
    Offset position, {
    required bool active,
  }) async {
    final workspace = context.read<WorkspaceController>();
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        PopupMenuItem(
          value: 'open',
          enabled: !asset.isOffline && !active,
          child: const ListTile(
            dense: true,
            leading: Icon(Icons.play_circle_outline),
            title: Text('Open as source'),
          ),
        ),
        PopupMenuItem(
          value: 'favorite',
          child: ListTile(
            dense: true,
            leading: Icon(asset.favorite ? Icons.star : Icons.star_border),
            title: Text(asset.favorite ? 'Remove favorite' : 'Add favorite'),
          ),
        ),
        if (asset.isOffline)
          const PopupMenuItem(
            value: 'relink',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.link),
              title: Text('Relink media'),
            ),
          ),
        for (final folder in _baseFolders.skip(1))
          PopupMenuItem(
            value: 'folder:$folder',
            enabled: asset.folder != folder,
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.drive_file_move_outline),
              title: Text('Move to $folder'),
            ),
          ),
        PopupMenuItem(
          value: 'remove',
          enabled: !active,
          child: const ListTile(
            dense: true,
            leading: Icon(Icons.delete_outline),
            title: Text('Remove from bin'),
          ),
        ),
      ],
    );
    if (!context.mounted || action == null) {
      return;
    }
    if (action == 'open') {
      await _activateMediaAssetPath(context, asset.path);
    } else if (action == 'relink') {
      await _relinkAsset(context, asset, active: active);
    } else if (action == 'favorite') {
      workspace.toggleAssetFavorite(asset);
    } else if (action == 'remove') {
      workspace.removeAsset(asset);
    } else if (action.startsWith('folder:')) {
      workspace.setAssetFolder(asset, action.substring('folder:'.length));
    }
  }

  Future<void> _relinkAsset(
    BuildContext context,
    AssetEntry asset, {
    required bool active,
  }) async {
    final editor = context.read<EditorController>();
    final workspace = context.read<WorkspaceController>();
    if (active) {
      await editor.relinkSourceMedia();
      if (!context.mounted) {
        return;
      }
      final replacement = editor.selectedFile;
      final path = replacement?.path;
      if (replacement != null && path != null && path.isNotEmpty) {
        workspace.relinkAsset(asset, name: replacement.name, path: path);
      }
      return;
    }
    final files = await editor.pickMediaAssets(allowMultiple: false);
    if (!context.mounted || files.isEmpty) {
      return;
    }
    final replacement = files.first;
    final path = replacement.path;
    if (path != null && path.isNotEmpty) {
      workspace.relinkAsset(asset, name: replacement.name, path: path);
    }
  }
}

class _MediaBinEmpty extends StatelessWidget {
  const _MediaBinEmpty({required this.onImport});

  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.video_library_outlined,
            size: 30,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 8),
          const Text('No media in this bin'),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onImport,
            icon: const Icon(Icons.add, size: 17),
            label: const Text('Import'),
          ),
        ],
      ),
    );
  }
}

class _MediaAssetTile extends StatelessWidget {
  const _MediaAssetTile({
    required this.asset,
    required this.active,
    required this.onOpen,
    required this.onFavorite,
    required this.onRelink,
    required this.onSecondaryTap,
  });

  final AssetEntry asset;
  final bool active;
  final VoidCallback? onOpen;
  final VoidCallback onFavorite;
  final VoidCallback? onRelink;
  final ValueChanged<Offset> onSecondaryTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final offline = asset.isOffline;
    final accent = offline
        ? colorScheme.error
        : active
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;
    final tile = GestureDetector(
      onTap: onOpen,
      onSecondaryTapDown: (details) => onSecondaryTap(details.globalPosition),
      child: Container(
        key: Key('media-asset-${asset.path}'),
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
        decoration: BoxDecoration(
          color: active
              ? colorScheme.primary.withValues(alpha: 0.11)
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.30),
          border: Border.all(
            color: active
                ? colorScheme.primary.withValues(alpha: 0.72)
                : offline
                ? colorScheme.error.withValues(alpha: 0.55)
                : colorScheme.outline.withValues(alpha: 0.72),
          ),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 30,
              child: Icon(
                offline ? Icons.link_off : _assetIcon(asset.name),
                color: accent,
                size: 20,
              ),
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    asset.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: offline ? colorScheme.error : null,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  Text(
                    offline
                        ? 'Offline · ${asset.folder}'
                        : active
                        ? 'Active source · ${asset.folder}'
                        : asset.folder,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: accent),
                  ),
                ],
              ),
            ),
            IconButton(
              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
              padding: EdgeInsets.zero,
              tooltip: asset.favorite ? 'Remove favorite' : 'Add favorite',
              onPressed: onFavorite,
              icon: Icon(
                asset.favorite ? Icons.star : Icons.star_border,
                size: 18,
                color: asset.favorite ? colorScheme.tertiary : null,
              ),
            ),
            if (offline)
              IconButton(
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
                padding: EdgeInsets.zero,
                tooltip: 'Relink media',
                onPressed: onRelink,
                icon: const Icon(Icons.link, size: 18),
              )
            else
              Icon(
                Icons.drag_indicator,
                size: 17,
                color: colorScheme.onSurfaceVariant,
              ),
          ],
        ),
      ),
    );
    if (offline) {
      return tile;
    }
    return Draggable<String>(
      data: asset.path,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(width: 270, child: Opacity(opacity: 0.94, child: tile)),
      ),
      childWhenDragging: Opacity(opacity: 0.42, child: tile),
      child: MouseRegion(cursor: SystemMouseCursors.click, child: tile),
    );
  }

  IconData _assetIcon(String name) {
    final extension = name.contains('.')
        ? name.split('.').last.toLowerCase()
        : '';
    if (const {'wav', 'mp3', 'aac', 'flac', 'm4a'}.contains(extension)) {
      return Icons.graphic_eq;
    }
    if (const {'png', 'jpg', 'jpeg', 'webp', 'gif'}.contains(extension)) {
      return Icons.image_outlined;
    }
    return Icons.movie_outlined;
  }
}

class _MediaActivityStrip extends StatelessWidget {
  const _MediaActivityStrip({required this.controller});

  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final failed = controller.errorMessage != null;
    final progress = controller.isUploading
        ? controller.uploadProgress
        : ((controller.job?.progress ?? 0) / 100).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: failed
            ? colorScheme.errorContainer.withValues(alpha: 0.20)
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        border: Border.all(
          color: failed ? colorScheme.error : colorScheme.outline,
        ),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                failed ? Icons.error_outline : Icons.sync,
                size: 16,
                color: failed ? colorScheme.error : colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  controller.statusText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ],
          ),
          if (!failed) ...[
            const SizedBox(height: 6),
            LinearProgressIndicator(value: progress > 0 ? progress : null),
          ],
        ],
      ),
    );
  }
}

enum _ProjectSwitchAction { save, discard }

Future<bool> _confirmProjectSwitch(BuildContext context) async {
  final editor = context.read<EditorController>();
  if (!editor.hasUnsavedProjectChanges) {
    return true;
  }
  final action = await showDialog<_ProjectSwitchAction>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Unsaved project'),
      content: Text('Save changes to ${editor.projectName} before switching?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.pop(dialogContext, _ProjectSwitchAction.discard),
          child: const Text('Switch without saving'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(dialogContext, _ProjectSwitchAction.save),
          child: const Text('Save and switch'),
        ),
      ],
    ),
  );
  if (!context.mounted || action == null) {
    return false;
  }
  if (action == _ProjectSwitchAction.save) {
    await editor.saveProjectFile();
    return !editor.hasUnsavedProjectChanges;
  }
  return true;
}

Future<void> _activateMediaAssetPath(
  BuildContext context,
  String path, {
  bool analyze = false,
}) async {
  final editor = context.read<EditorController>();
  if (editor.sourceMediaPath != path) {
    if (!await _confirmProjectSwitch(context) || !context.mounted) {
      return;
    }
    await editor.openMediaPath(path);
  }
  if (analyze && editor.canStartUpload) {
    await editor.dropSelectedFileOnTimeline();
  }
}

class _PreviewStage extends StatelessWidget {
  const _PreviewStage();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<EditorController>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: _SurfacePanel(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            _PreviewHeader(
              timecode: formatSeconds(controller.currentPositionSeconds),
              duration: formatSeconds(controller.duration),
              sourceLabel: controller.previewSourceLabel,
              audioLabel: controller.previewAudioLabel,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final aspect = switch (controller.exportAspectRatio) {
                      '9:16' => 9 / 16,
                      '1:1' => 1.0,
                      _ => 16 / 9,
                    };
                    var width = constraints.maxWidth;
                    var height = width / aspect;
                    if (height > constraints.maxHeight) {
                      height = constraints.maxHeight;
                      width = height * aspect;
                    }
                    return Center(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: Theme.of(
                              context,
                            ).colorScheme.outline.withValues(alpha: 0.75),
                          ),
                        ),
                        child: SizedBox(
                          width: width,
                          height: height,
                          child: VideoPreview(
                            controller: controller.videoController,
                            volume: controller.previewVolume,
                            muted: controller.previewMuted,
                            targetAspectRatio: aspect,
                            focusX: controller.selectedSegment?.focusX ?? 0.5,
                            focusY: controller.selectedSegment?.focusY ?? 0.42,
                            focusKeyframes:
                                controller.selectedSegment?.focusKeyframes ??
                                const [],
                            segmentStart:
                                controller.selectedSegment?.start ?? 0,
                            onToggleMute: context
                                .read<EditorController>()
                                .togglePreviewMute,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelinePanel extends StatelessWidget {
  const _TimelinePanel({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<EditorController>();
    final editor = context.read<EditorController>();
    final timelineContent = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: Row(
            children: [
              const _PanelHeader(
                title: 'Timeline',
                icon: Icons.view_timeline_outlined,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _SmallPill(label: '${controller.segments.length} clips'),
                      const SizedBox(width: 6),
                      _TrackControlButton(
                        label: controller.timelineSnappingLabel,
                        icon: controller.timelineSnappingEnabled
                            ? Icons.grid_on
                            : Icons.grid_off,
                        tooltip: controller.timelineSnappingEnabled
                            ? '타임라인 스냅 끄기 (S)'
                            : '타임라인 스냅 켜기 (S)',
                        selected: controller.timelineSnappingEnabled,
                        onPressed: editor.toggleTimelineSnapping,
                      ),
                      const SizedBox(width: 6),
                      _TrackControlButton(
                        label: controller.timelineTrackHeightLabel,
                        icon: Icons.height,
                        tooltip: '트랙 높이 변경 (Alt+- / Alt+=)',
                        selected: controller.timelineTrackHeightScale > 1.05,
                        onPressed: editor.cycleTimelineTrackHeight,
                      ),
                      const SizedBox(width: 6),
                      _AudioTrackBusMenu(
                        controller: controller,
                        editor: editor,
                      ),
                      const SizedBox(width: 6),
                      const _SmallPill(label: '30p NDF'),
                      const SizedBox(width: 6),
                      _SmallPill(
                        label:
                            'Out ${formatSeconds(controller.segments.fold<double>(0, (total, segment) => total + segment.outputDuration))}',
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: EditControls(),
        ),
        const SizedBox(height: 8),
        if (compact)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: _TimelineEditorBody(controller: controller),
          )
        else
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: _TimelineEditorBody(controller: controller),
            ),
          ),
      ],
    );
    return Padding(
      padding: compact
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: _SurfacePanel(
        padding: EdgeInsets.zero,
        child: _TimelineDropTarget(child: timelineContent),
      ),
    );
  }
}

class _TimelineDropTarget extends StatelessWidget {
  const _TimelineDropTarget({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final workspace = context.watch<WorkspaceController>();
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) {
        return workspace.assets.any(
          (asset) => asset.path == details.data && !asset.isOffline,
        );
      },
      onAcceptWithDetails: (details) {
        unawaited(
          _activateMediaAssetPath(context, details.data, analyze: true),
        );
      },
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;
        return Stack(
          children: [
            child,
            if (isHovering)
              Positioned.fill(
                child: IgnorePointer(
                  child: _TimelineDropOverlay(
                    message: 'Drop to analyze on V1/A1',
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _TimelineDropOverlay extends StatelessWidget {
  const _TimelineDropOverlay({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.12),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.72),
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: colorScheme.outline),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Text(message, style: Theme.of(context).textTheme.labelLarge),
          ),
        ),
      ),
    );
  }
}

class _InspectorPanel extends StatelessWidget {
  const _InspectorPanel();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<EditorController>();
    return Padding(
      padding: const EdgeInsets.all(12),
      child: _SurfacePanel(
        padding: const EdgeInsets.all(12),
        child: DefaultTabController(
          length: 5,
          initialIndex: const bool.fromEnvironment('AUTOEDIT_DEMO') ? 1 : 0,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const TabBar(
                tabs: [
                  Tab(icon: Icon(Icons.auto_awesome), text: 'Clips'),
                  Tab(icon: Icon(Icons.auto_fix_high), text: 'AI'),
                  Tab(icon: Icon(Icons.bookmarks_outlined), text: 'Markers'),
                  Tab(
                    icon: Icon(Icons.closed_caption_outlined),
                    text: 'Captions',
                  ),
                  Tab(icon: Icon(Icons.tune), text: 'Properties'),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: TabBarView(
                  children: [
                    controller.segments.isEmpty
                        ? Center(
                            child: Text(
                              '분석 후 추천 클립이 표시됩니다',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          )
                        : HighlightCards(
                            segments: controller.segments,
                            onSeek: context.read<EditorController>().seekTo,
                            selectedOrder: controller.selectedSegmentOrder,
                            onSelect: context
                                .read<EditorController>()
                                .selectSegment,
                          ),
                    const AiDirectorPanel(),
                    const TimelineMarkerPanel(),
                    CaptionEditor(
                      captions: controller.captions,
                      onChanged: context.read<EditorController>().updateCaption,
                      onToggle: context.read<EditorController>().toggleCaption,
                      onSeek: context.read<EditorController>().seekTo,
                    ),
                    const ClipInspector(),
                  ],
                ),
              ),
              if (controller.renderOutputs.isNotEmpty) ...[
                const SizedBox(height: 10),
                RenderOutputsPanel(
                  outputs: controller.renderOutputs,
                  compact: true,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TimelineEditorBody extends StatelessWidget {
  const _TimelineEditorBody({required this.controller});

  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    return TimelineEditor(
      duration: controller.timelineSourceDuration,
      segments: controller.segments,
      playheadSeconds: controller.currentPositionSeconds,
      selectedSegmentOrder: controller.selectedSegmentOrder,
      markIn: controller.markIn,
      markOut: controller.markOut,
      timelineMarkers: controller.timelineMarkers,
      waveform: controller.waveform,
      zoom: controller.timelineZoom,
      trackHeightScale: controller.timelineTrackHeightScale,
      snappingEnabled: controller.timelineSnappingEnabled,
      videoTrackTargeted: controller.videoTrackTargeted,
      audioTrack1Targeted: controller.audioTrack1Targeted,
      audioTrack2Targeted: controller.audioTrack2Targeted,
      videoTrackLocked: controller.videoTrackLocked,
      audioTrackLocked: controller.audioTrackLocked,
      audioTrack1Locked: controller.audioTrack1Locked,
      audioTrack2Locked: controller.audioTrack2Locked,
      razorTool: controller.isRazorTool,
      onSegmentChanged: context.read<EditorController>().updateSegment,
      onScrub: (seconds) {
        context.read<EditorController>().seekTo(seconds, autoplay: false);
      },
      onSegmentSelected: context.read<EditorController>().selectSegment,
      onSetMarkIn: context.read<EditorController>().setMarkInAt,
      onSetMarkOut: context.read<EditorController>().setMarkOutAt,
      onClearMarks: context.read<EditorController>().clearMarks,
      onClearMarkIn: context.read<EditorController>().clearMarkIn,
      onClearMarkOut: context.read<EditorController>().clearMarkOut,
      onLiftMarkedRange: context.read<EditorController>().liftMarkedRange,
      onExtractMarkedRange: context.read<EditorController>().extractMarkedRange,
      onInsertMarkedSegment: context
          .read<EditorController>()
          .insertMarkedSegmentAtSelection,
      onOverwriteMarkedSegment: context
          .read<EditorController>()
          .overwriteSelectedSegmentWithMarks,
      onStepBackwardFrame: () =>
          unawaited(context.read<EditorController>().stepPlayheadByFrames(-1)),
      onStepForwardFrame: () =>
          unawaited(context.read<EditorController>().stepPlayheadByFrames(1)),
      onJumpToPreviousEdit: () =>
          unawaited(context.read<EditorController>().jumpToPreviousEditPoint()),
      onJumpToNextEdit: () =>
          unawaited(context.read<EditorController>().jumpToNextEditPoint()),
      onJumpToMarkIn: () =>
          unawaited(context.read<EditorController>().jumpToMarkIn()),
      onJumpToMarkOut: () =>
          unawaited(context.read<EditorController>().jumpToMarkOut()),
      onJumpToSelectedClipStart: () =>
          unawaited(context.read<EditorController>().jumpToSelectedClipStart()),
      onJumpToSelectedClipEnd: () =>
          unawaited(context.read<EditorController>().jumpToSelectedClipEnd()),
      onSlipSelectedSegmentFrames: context
          .read<EditorController>()
          .slipSelectedSegmentFrames,
      onNudgeSelectedAudioFrames: context
          .read<EditorController>()
          .nudgeSelectedAudioFrames,
      onAddMarkerAt: context.read<EditorController>().addTimelineMarkerAt,
      onJumpToPreviousMarker: context
          .read<EditorController>()
          .jumpToPreviousTimelineMarker,
      onJumpToNextMarker: context
          .read<EditorController>()
          .jumpToNextTimelineMarker,
      onDeleteMarker: context.read<EditorController>().deleteTimelineMarker,
      onClearTimelineMarkers: context
          .read<EditorController>()
          .clearTimelineMarkers,
      onMarkClip: context.read<EditorController>().markSelectedClip,
      onSelectClipAt: context.read<EditorController>().selectSegmentAt,
      onDeselectClip: context.read<EditorController>().clearSegmentSelection,
      onSelectPreviousClip: context
          .read<EditorController>()
          .selectPreviousSegment,
      onSelectNextClip: context.read<EditorController>().selectNextSegment,
      onAddEditAt: context.read<EditorController>().addEditAt,
      onAddEditAllTracksAt: context
          .read<EditorController>()
          .addEditToAllTracksAt,
      onRippleTrimStartTo: context
          .read<EditorController>()
          .rippleTrimSelectedStartTo,
      onRippleTrimEndTo: context
          .read<EditorController>()
          .rippleTrimSelectedEndTo,
      onExtendStartTo: context.read<EditorController>().extendSelectedStartTo,
      onExtendEndTo: context.read<EditorController>().extendSelectedEndTo,
      onRollIncomingEditFrames: context
          .read<EditorController>()
          .rollSelectedIncomingEditFrames,
      onRollOutgoingEditFrames: context
          .read<EditorController>()
          .rollSelectedOutgoingEditFrames,
      onApplyVideoTransition: context
          .read<EditorController>()
          .applyDefaultVideoTransition,
      onApplyAudioTransition: context
          .read<EditorController>()
          .applyDefaultAudioTransition,
      onRateStretchToMarks: context
          .read<EditorController>()
          .rateStretchSelectedToMarks,
      onSetSelectionTool: context.read<EditorController>().setSelectionTool,
      onSetRazorTool: context.read<EditorController>().setRazorTool,
      onToggleSnapping: context.read<EditorController>().toggleTimelineSnapping,
      onSplitAt: context.read<EditorController>().splitSelectedAt,
      onDuplicateSegment: context
          .read<EditorController>()
          .duplicateSelectedSegment,
      onCopySegment: context.read<EditorController>().copySelectedSegment,
      onCutSegment: context.read<EditorController>().cutSelectedSegment,
      onPasteSegment: context.read<EditorController>().pasteClipboardSegment,
      hasClipClipboard: controller.hasClipClipboard,
      onDeleteSegment: context.read<EditorController>().deleteSelectedSegment,
      hasTimelineGaps: controller.hasTimelineGaps,
      onCloseSelectedGap: context
          .read<EditorController>()
          .closeSelectedTimelineGap,
      onCloseTimelineGaps: context.read<EditorController>().closeTimelineGaps,
      onLiftSelectedSegment: context
          .read<EditorController>()
          .liftSelectedSegment,
      onExtractSelectedSegment: context
          .read<EditorController>()
          .extractSelectedSegment,
      onMoveSegment: context.read<EditorController>().moveSelectedSegment,
      onToggleAudioLink: context
          .read<EditorController>()
          .toggleSelectedAudioLink,
      onToggleAudioMute: context
          .read<EditorController>()
          .toggleSelectedAudioMute,
      onToggleAudioChannel1: context
          .read<EditorController>()
          .toggleSelectedAudioChannel1,
      onToggleAudioChannel2: context
          .read<EditorController>()
          .toggleSelectedAudioChannel2,
      onToggleAllAudioChannel1: context
          .read<EditorController>()
          .toggleAllAudioChannel1,
      onToggleAllAudioChannel2: context
          .read<EditorController>()
          .toggleAllAudioChannel2,
      onSoloAudioChannel1: context
          .read<EditorController>()
          .soloAudioChannel1Track,
      onSoloAudioChannel2: context
          .read<EditorController>()
          .soloAudioChannel2Track,
      onToggleVideoTarget: context
          .read<EditorController>()
          .toggleVideoTrackTarget,
      onToggleAudio1Target: context
          .read<EditorController>()
          .toggleAudioTrack1Target,
      onToggleAudio2Target: context
          .read<EditorController>()
          .toggleAudioTrack2Target,
      onToggleVideoLock: context.read<EditorController>().toggleVideoTrackLock,
      onToggleAudio1Lock: context
          .read<EditorController>()
          .toggleAudioTrack1Lock,
      onToggleAudio2Lock: context
          .read<EditorController>()
          .toggleAudioTrack2Lock,
      onToggleClipEnabled: context
          .read<EditorController>()
          .toggleSelectedClipEnabled,
      onToggleVideoEnabled: context
          .read<EditorController>()
          .toggleSelectedVideoEnabled,
      onResetAudioPan: context.read<EditorController>().resetSelectedAudioPan,
      onZoomDelta: context.read<EditorController>().zoomTimeline,
    );
  }
}

class _EngineStatus extends StatelessWidget {
  const _EngineStatus();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<EditorController>();
    final state = controller.engineState;
    final color = state.status == 'browser'
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : state.isRunning
        ? Theme.of(context).colorScheme.primary
        : state.isStarting
        ? Theme.of(context).colorScheme.tertiary
        : Theme.of(context).colorScheme.error;

    return _SurfacePanel(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(Icons.memory_outlined, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              state.message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          IconButton(
            tooltip: '엔진 다시 확인',
            onPressed: state.isStarting || !state.canStart
                ? null
                : context.read<EditorController>().ensureLocalEngine,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }
}

class _WorkspaceRail extends StatelessWidget {
  const _WorkspaceRail();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFF101217)),
      child: Column(
        children: const [
          SizedBox(height: 10),
          _RailButton(
            icon: Icons.perm_media_outlined,
            label: 'Media',
            active: true,
          ),
          _RailButton(icon: Icons.content_cut, label: 'Edit'),
          _RailButton(icon: Icons.auto_awesome, label: 'AI'),
          _RailButton(icon: Icons.closed_caption_outlined, label: 'Text'),
          Spacer(),
          _RailButton(icon: Icons.settings_outlined, label: 'Settings'),
          SizedBox(height: 10),
        ],
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.icon,
    required this.label,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = active ? colorScheme.primary : colorScheme.onSurfaceVariant;
    return Tooltip(
      message: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: active
                ? colorScheme.primary.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: active
                ? Border.all(color: colorScheme.primary.withValues(alpha: 0.45))
                : null,
          ),
          child: Icon(icon, size: 21, color: color),
        ),
      ),
    );
  }
}

class _WorkspaceTab extends StatelessWidget {
  const _WorkspaceTab({required this.label, this.selected = false});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: selected
            ? colorScheme.primary.withValues(alpha: 0.14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: selected ? colorScheme.primary : Colors.transparent,
        ),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
    );
  }
}

class _PreviewHeader extends StatelessWidget {
  const _PreviewHeader({
    required this.timecode,
    required this.duration,
    required this.sourceLabel,
    required this.audioLabel,
  });

  final String timecode;
  final String duration;
  final String sourceLabel;
  final String audioLabel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF121419),
        border: Border(bottom: BorderSide(color: colorScheme.outline)),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
      ),
      child: Row(
        children: [
          const _PanelHeader(title: 'Program', icon: Icons.live_tv_outlined),
          const SizedBox(width: 12),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(
                children: [
                  _SmallPill(label: sourceLabel),
                  const SizedBox(width: 8),
                  _SmallPill(label: audioLabel),
                  const SizedBox(width: 8),
                  _SmallPill(label: timecode),
                  const SizedBox(width: 8),
                  Text(
                    duration,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallPill extends StatelessWidget {
  const _SmallPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colorScheme.outline),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colorScheme.onSurface,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _TrackControlButton extends StatelessWidget {
  const _TrackControlButton({
    required this.label,
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: selected
              ? colorScheme.primary
              : colorScheme.onSurface,
          backgroundColor: selected
              ? colorScheme.primary.withValues(alpha: 0.10)
              : colorScheme.surfaceContainerHighest,
          side: BorderSide(
            color: selected ? colorScheme.primary : colorScheme.outline,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          minimumSize: const Size(0, 32),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
    );
  }
}

class _AudioTrackBusMenu extends StatelessWidget {
  const _AudioTrackBusMenu({required this.controller, required this.editor});

  final EditorController controller;
  final EditorController editor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final enabled =
        controller.hasTimeline && !controller.anyAudioTrackEditLocked;
    return Tooltip(
      message: enabled ? 'A1/A2 전체 트랙 제어' : 'A1/A2 트랙 잠김',
      child: PopupMenuButton<String>(
        enabled: enabled,
        tooltip: 'A1/A2 전체 트랙 제어',
        onSelected: (value) {
          switch (value) {
            case 'toggle-a1':
              editor.toggleAllAudioChannel1();
              break;
            case 'toggle-a2':
              editor.toggleAllAudioChannel2();
              break;
            case 'solo-a1':
              editor.soloAudioChannel1Track();
              break;
            case 'solo-a2':
              editor.soloAudioChannel2Track();
              break;
          }
        },
        itemBuilder: (context) => [
          _audioBusItem(
            value: 'toggle-a1',
            icon: controller.allAudioChannel1Enabled
                ? Icons.check_box_outlined
                : Icons.check_box_outline_blank,
            label: controller.allAudioChannel1Enabled
                ? 'Disable all A1'
                : 'Enable all A1',
          ),
          _audioBusItem(
            value: 'toggle-a2',
            icon: controller.allAudioChannel2Enabled
                ? Icons.check_box_outlined
                : Icons.check_box_outline_blank,
            label: controller.allAudioChannel2Enabled
                ? 'Disable all A2'
                : 'Enable all A2',
          ),
          const PopupMenuDivider(),
          _audioBusItem(
            value: 'solo-a1',
            icon: Icons.filter_1_outlined,
            label: 'Solo A1 track',
          ),
          _audioBusItem(
            value: 'solo-a2',
            icon: Icons.filter_2_outlined,
            label: 'Solo A2 track',
          ),
        ],
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: enabled ? colorScheme.outline : colorScheme.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.graphic_eq,
                size: 16,
                color: enabled
                    ? colorScheme.onSurface
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                'Audio Bus',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: enabled
                      ? colorScheme.onSurface
                      : colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  PopupMenuItem<String> _audioBusItem({
    required String value,
    required IconData icon,
    required String label,
  }) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [Icon(icon, size: 18), const SizedBox(width: 8), Text(label)],
      ),
    );
  }
}

class _EnginePill extends StatelessWidget {
  const _EnginePill({required this.stateText});

  final String stateText;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.circle,
            size: 9,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              stateText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _SurfacePanel extends StatelessWidget {
  const _SurfacePanel({required this.child, this.padding = EdgeInsets.zero});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _VerticalRule extends StatelessWidget {
  const _VerticalRule();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, color: Theme.of(context).colorScheme.outline);
  }
}
