import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:video_player_media_kit/video_player_media_kit.dart';

import 'state/editor_controller.dart';
import 'widgets/ai_director_panel.dart';
import 'widgets/caption_editor.dart';
import 'widgets/clip_inspector.dart';
import 'widgets/edit_controls.dart';
import 'widgets/highlight_cards.dart';
import 'widgets/status_panel.dart';
import 'widgets/time_format.dart';
import 'widgets/timeline_editor.dart';
import 'widgets/video_preview.dart';

void main() {
  VideoPlayerMediaKit.ensureInitialized(windows: true);
  runApp(
    ChangeNotifierProvider(
      create: (_) => EditorController(),
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
  const EditorDashboard({super.key});

  @override
  State<EditorDashboard> createState() => _EditorDashboardState();
}

class _EditorDashboardState extends State<EditorDashboard> {
  final FocusNode _shortcutFocusNode = FocusNode(
    debugLabel: 'AutoEdit shortcuts',
  );

  @override
  void dispose() {
    _shortcutFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _shortcutFocusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final useDesktop =
                  constraints.maxWidth >= 1120 && constraints.maxHeight >= 680;
              return useDesktop
                  ? const _DesktopEditorShell()
                  : const _CompactEditorShell();
            },
          ),
        ),
      ),
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final keyboard = HardwareKeyboard.instance;
    final isCtrl = keyboard.isControlPressed || keyboard.isMetaPressed;
    final isShift = keyboard.isShiftPressed;
    final isAlt = keyboard.isAltPressed;
    final key = event.logicalKey;
    final editor = context.read<EditorController>();

    bool handled = true;
    if (isCtrl && isShift && key == LogicalKeyboardKey.keyZ) {
      editor.redo();
    } else if (isCtrl && !isShift && key == LogicalKeyboardKey.keyZ) {
      editor.undo();
    } else if (isCtrl && key == LogicalKeyboardKey.keyK) {
      editor.addEditAtPlayhead();
    } else if (isCtrl && isShift && key == LogicalKeyboardKey.keyD) {
      editor.applyDefaultAudioTransition();
    } else if (isCtrl && !isShift && key == LogicalKeyboardKey.keyD) {
      editor.applyDefaultVideoTransition();
    } else if (isCtrl && isShift && key == LogicalKeyboardKey.keyX) {
      editor.clearMarks();
    } else if (isCtrl && isShift && key == LogicalKeyboardKey.keyI) {
      editor.clearMarkIn();
    } else if (isCtrl && isShift && key == LogicalKeyboardKey.keyO) {
      editor.clearMarkOut();
    } else if (!isCtrl &&
        !isAlt &&
        !isShift &&
        key == LogicalKeyboardKey.keyC) {
      editor.setRazorTool();
    } else if (!isCtrl &&
        !isAlt &&
        !isShift &&
        key == LogicalKeyboardKey.keyV) {
      editor.setSelectionTool();
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
    } else if (!isCtrl &&
        !isAlt &&
        !isShift &&
        key == LogicalKeyboardKey.keyX) {
      editor.markSelectedClip();
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
    } else if (key == LogicalKeyboardKey.delete) {
      editor.deleteSelectedSegment();
    } else {
      handled = false;
    }

    return handled ? KeyEventResult.handled : KeyEventResult.ignored;
  }
}

class _DesktopEditorShell extends StatelessWidget {
  const _DesktopEditorShell();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _TopBar(),
        const _CommandBar(),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: const [
              SizedBox(width: 56, child: _WorkspaceRail()),
              _VerticalRule(),
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(width: 320, child: _MediaPanel()),
                          _VerticalRule(),
                          Expanded(child: _PreviewStage()),
                          _VerticalRule(),
                          SizedBox(width: 384, child: _InspectorPanel()),
                        ],
                      ),
                    ),
                    _HorizontalRule(),
                    SizedBox(height: 330, child: _TimelinePanel()),
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

class _CompactEditorShell extends StatelessWidget {
  const _CompactEditorShell();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<EditorController>();
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
              _SurfacePanel(
                padding: const EdgeInsets.all(12),
                child: VideoPreview(controller: controller.videoController),
              ),
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
                Text(
                  controller.projectName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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
              onPressed: controller.hasTimeline
                  ? () => editor.saveProjectToBackend()
                  : null,
            ),
            _ToolbarButton(
              icon: Icons.file_download_outlined,
              label: 'Project',
              onPressed: controller.hasTimeline
                  ? editor.exportProjectFile
                  : null,
            ),
            _ToolbarButton(
              icon: Icons.folder_open,
              label: 'Open',
              onPressed: editor.importProjectFile,
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
            const _ToolbarDivider(),
            IconButton.outlined(
              tooltip: '타임라인 축소',
              onPressed: controller.hasTimeline
                  ? () => editor.zoomTimeline(-0.5)
                  : null,
              icon: const Icon(Icons.zoom_out),
            ),
            const SizedBox(width: 6),
            IconButton.outlined(
              tooltip: '타임라인 확대',
              onPressed: controller.hasTimeline
                  ? () => editor.zoomTimeline(0.5)
                  : null,
              icon: const Icon(Icons.zoom_in),
            ),
            const SizedBox(width: 10),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: '16:9', label: Text('16:9')),
                ButtonSegment(value: '9:16', label: Text('9:16')),
              ],
              selected: {controller.exportAspectRatio},
              onSelectionChanged: controller.hasTimeline
                  ? (value) => editor.setExportAspectRatio(value.first)
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
                controller.renderUrl == null ? 'Export' : 'Re-export',
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

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const [
          _PanelHeader(title: 'Project Media', icon: Icons.perm_media_outlined),
          SizedBox(height: 10),
          _EngineStatus(),
          SizedBox(height: 10),
          StatusPanel(),
          Spacer(),
        ],
      ),
    );
  }
}

class _PreviewStage extends StatelessWidget {
  const _PreviewStage();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<EditorController>();
    return Padding(
      padding: const EdgeInsets.all(14),
      child: _SurfacePanel(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            _PreviewHeader(
              timecode: formatSeconds(controller.currentPositionSeconds),
              duration: formatSeconds(controller.duration),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    const aspect = 16 / 9;
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
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                        child: SizedBox(
                          width: width,
                          height: height,
                          child: VideoPreview(
                            controller: controller.videoController,
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
    return Padding(
      padding: compact
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: _SurfacePanel(
        padding: EdgeInsets.zero,
        child: controller.hasTimeline
            ? Column(
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
                        _SmallPill(
                          label: '${controller.segments.length} clips',
                        ),
                        const SizedBox(width: 6),
                        _TrackControlButton(
                          label: controller.videoTrackLocked
                              ? 'V1 Locked'
                              : 'V1',
                          icon: controller.videoTrackLocked
                              ? Icons.lock
                              : Icons.lock_open,
                          tooltip: controller.videoTrackLocked
                              ? 'V1 영상 트랙 잠금 해제'
                              : 'V1 영상 트랙 잠금',
                          selected: controller.videoTrackLocked,
                          onPressed: editor.toggleVideoTrackLock,
                        ),
                        const SizedBox(width: 6),
                        _TrackControlButton(
                          label: controller.audioTrackLocked
                              ? 'A1 Locked'
                              : 'A1',
                          icon: controller.audioTrackLocked
                              ? Icons.lock
                              : Icons.lock_open,
                          tooltip: controller.audioTrackLocked
                              ? 'A1 오디오 트랙 잠금 해제'
                              : 'A1 오디오 트랙 잠금',
                          selected: controller.audioTrackLocked,
                          onPressed: editor.toggleAudioTrackLock,
                        ),
                        const SizedBox(width: 6),
                        _TrackControlButton(
                          label: controller.allAudioMuted
                              ? 'A1 Muted'
                              : 'A1 Mix',
                          icon: controller.allAudioMuted
                              ? Icons.volume_off_outlined
                              : Icons.volume_up_outlined,
                          tooltip: controller.allAudioMuted
                              ? 'A1 전체 음소거 해제'
                              : 'A1 전체 음소거',
                          selected: controller.allAudioMuted,
                          onPressed: editor.toggleAllAudioMute,
                        ),
                        const Spacer(),
                        _SmallPill(
                          label:
                              'Out ${formatSeconds(controller.segments.fold<double>(0, (total, segment) => total + segment.outputDuration))}',
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
              )
            : Center(
                child: SizedBox(
                  height: compact ? 150 : null,
                  child: Center(
                    child: Text(
                      controller.job?.stage == 'queued'
                          ? '분석 대기 중'
                          : '타임라인 대기 중',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
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
          length: 4,
          initialIndex: const bool.fromEnvironment('AUTOEDIT_DEMO') ? 1 : 0,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const TabBar(
                tabs: [
                  Tab(icon: Icon(Icons.auto_awesome), text: 'Clips'),
                  Tab(icon: Icon(Icons.auto_fix_high), text: 'AI'),
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
              if (controller.renderUrl != null) ...[
                const SizedBox(height: 10),
                SelectableText(
                  controller.renderUrl!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
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
      duration: controller.duration,
      segments: controller.segments,
      playheadSeconds: controller.currentPositionSeconds,
      selectedSegmentOrder: controller.selectedSegmentOrder,
      markIn: controller.markIn,
      markOut: controller.markOut,
      waveform: controller.waveform,
      zoom: controller.timelineZoom,
      videoTrackLocked: controller.videoTrackLocked,
      audioTrackLocked: controller.audioTrackLocked,
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
      onMarkClip: context.read<EditorController>().markSelectedClip,
      onAddEditAt: context.read<EditorController>().addEditAt,
      onRippleTrimStartTo: context
          .read<EditorController>()
          .rippleTrimSelectedStartTo,
      onRippleTrimEndTo: context
          .read<EditorController>()
          .rippleTrimSelectedEndTo,
      onExtendStartTo: context.read<EditorController>().extendSelectedStartTo,
      onExtendEndTo: context.read<EditorController>().extendSelectedEndTo,
      onApplyVideoTransition: context
          .read<EditorController>()
          .applyDefaultVideoTransition,
      onApplyAudioTransition: context
          .read<EditorController>()
          .applyDefaultAudioTransition,
      onSetSelectionTool: context.read<EditorController>().setSelectionTool,
      onSetRazorTool: context.read<EditorController>().setRazorTool,
      onSplitAt: context.read<EditorController>().splitSelectedAt,
      onDuplicateSegment: context
          .read<EditorController>()
          .duplicateSelectedSegment,
      onDeleteSegment: context.read<EditorController>().deleteSelectedSegment,
      onMoveSegment: context.read<EditorController>().moveSelectedSegment,
      onToggleAudioLink: context
          .read<EditorController>()
          .toggleSelectedAudioLink,
      onToggleAudioMute: context
          .read<EditorController>()
          .toggleSelectedAudioMute,
      onToggleVideoEnabled: context
          .read<EditorController>()
          .toggleSelectedVideoEnabled,
      onResetAudioPan: context.read<EditorController>().resetSelectedAudioPan,
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
  const _PreviewHeader({required this.timecode, required this.duration});

  final String timecode;
  final String duration;

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
          const Spacer(),
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

class _HorizontalRule extends StatelessWidget {
  const _HorizontalRule();

  @override
  Widget build(BuildContext context) {
    return Container(height: 1, color: Theme.of(context).colorScheme.outline);
  }
}
