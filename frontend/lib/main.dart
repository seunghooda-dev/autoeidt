import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player_media_kit/video_player_media_kit.dart';

import 'state/editor_controller.dart';
import 'widgets/edit_controls.dart';
import 'widgets/highlight_cards.dart';
import 'widgets/status_panel.dart';
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
    const seed = Color(0xFF14B8A6);
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
          tertiary: const Color(0xFFF59E0B),
          surface: const Color(0xFF1F1F22),
          surfaceContainerHighest: const Color(0xFF2B2B30),
          outline: const Color(0xFF45454D),
        ),
        scaffoldBackgroundColor: const Color(0xFF171719),
        fontFamily: 'Arial',
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
              SizedBox(width: 310, child: _MediaPanel()),
              _VerticalRule(),
              Expanded(child: _CenterEditor()),
              _VerticalRule(),
              SizedBox(width: 360, child: _InspectorPanel()),
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
        SizedBox(height: 272, child: _TimelinePanel()),
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
      height: compact ? 56 : 60,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF202023),
        border: Border(
          bottom: BorderSide(color: Theme.of(context).colorScheme.outline),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome_motion, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'AI 하이라이트 편집기',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
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
          _PanelHeader(title: 'Media', icon: Icons.perm_media_outlined),
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
        padding: const EdgeInsets.all(12),
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
              child: SizedBox(
                width: width,
                height: height,
                child: VideoPreview(controller: controller.videoController),
              ),
            );
          },
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
        padding: const EdgeInsets.all(12),
        child: controller.hasTimeline
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const _PanelHeader(
                        title: 'Timeline',
                        icon: Icons.view_timeline_outlined,
                      ),
                      const Spacer(),
                      Text(
                        '${controller.segments.length} clips',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const EditControls(),
                  const SizedBox(height: 10),
                  TimelineEditor(
                    duration: controller.duration,
                    segments: controller.segments,
                    playheadSeconds: controller.currentPositionSeconds,
                    selectedSegmentOrder: controller.selectedSegmentOrder,
                    markIn: controller.markIn,
                    markOut: controller.markOut,
                    onSegmentChanged: context
                        .read<EditorController>()
                        .updateSegment,
                    onScrub: (seconds) {
                      context.read<EditorController>().seekTo(
                        seconds,
                        autoplay: false,
                      );
                    },
                    onSegmentSelected: context
                        .read<EditorController>()
                        .selectSegment,
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
    final cards = HighlightCards(
      segments: controller.segments,
      onSeek: context.read<EditorController>().seekTo,
      selectedOrder: controller.selectedSegmentOrder,
      onSelect: context.read<EditorController>().selectSegment,
    );

    return Padding(
      padding: const EdgeInsets.all(12),
      child: _SurfacePanel(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _PanelHeader(title: 'AI Clips', icon: Icons.auto_awesome),
            const SizedBox(height: 10),
            Expanded(
              child: controller.segments.isEmpty
                  ? Center(
                      child: Text(
                        '분석 후 추천 클립이 표시됩니다',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    )
                  : cards,
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
