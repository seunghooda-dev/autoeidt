import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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

class EditorDashboard extends StatelessWidget {
  const EditorDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
    );
  }
}

class _DesktopEditorShell extends StatelessWidget {
  const _DesktopEditorShell();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _TopBar(),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: const [
              SizedBox(width: 56, child: _WorkspaceRail()),
              _VerticalRule(),
              SizedBox(width: 304, child: _MediaPanel()),
              _VerticalRule(),
              Expanded(child: _CenterEditor()),
              _VerticalRule(),
              SizedBox(width: 372, child: _InspectorPanel()),
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

class _CenterEditor extends StatelessWidget {
  const _CenterEditor();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: const [
        Expanded(child: _PreviewStage()),
        _HorizontalRule(),
        SizedBox(height: 326, child: _TimelinePanel()),
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
          FilledButton.icon(
            onPressed: controller.canRender
                ? context.read<EditorController>().requestRender
                : null,
            icon: const Icon(Icons.file_upload_outlined),
            label: Text(controller.renderUrl == null ? 'Export' : 'Re-export'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: controller.canRender
                ? context.read<EditorController>().requestShortsRender
                : null,
            icon: const Icon(Icons.phone_iphone),
            label: const Text('Shorts'),
          ),
        ],
      ),
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
      onSegmentChanged: context.read<EditorController>().updateSegment,
      onScrub: (seconds) {
        context.read<EditorController>().seekTo(seconds, autoplay: false);
      },
      onSegmentSelected: context.read<EditorController>().selectSegment,
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
