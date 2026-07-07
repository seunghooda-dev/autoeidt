import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'state/editor_controller.dart';
import 'widgets/edit_controls.dart';
import 'widgets/highlight_cards.dart';
import 'widgets/status_panel.dart';
import 'widgets/timeline_editor.dart';
import 'widgets/video_preview.dart';

void main() {
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
    return MaterialApp(
      title: 'AI Highlight Editor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F766E),
          primary: const Color(0xFF0F766E),
          tertiary: const Color(0xFFF97316),
          surface: const Color(0xFFF8FAFC),
        ),
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
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
      appBar: AppBar(title: const Text('AI 하이라이트 편집기'), centerTitle: false),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 1080) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(width: 380, child: _SidePanel()),
                    const SizedBox(width: 20),
                    Expanded(
                      child: _Workspace(maxHeight: constraints.maxHeight),
                    ),
                  ],
                );
              }
              return SingleChildScrollView(
                child: Column(
                  children: [
                    const _SidePanel(compact: true),
                    const SizedBox(height: 20),
                    _Workspace(maxHeight: constraints.maxHeight),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SidePanel extends StatelessWidget {
  const _SidePanel({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<EditorController>();
    final cards = HighlightCards(
      segments: controller.segments,
      onSeek: context.read<EditorController>().seekTo,
      selectedOrder: controller.selectedSegmentOrder,
      onSelect: context.read<EditorController>().selectSegment,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StatusPanel(),
        const SizedBox(height: 16),
        if (compact)
          SizedBox(height: 360, child: cards)
        else
          Expanded(child: cards),
      ],
    );
  }
}

class _Workspace extends StatelessWidget {
  const _Workspace({required this.maxHeight});

  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<EditorController>();
    return SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: maxHeight),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            VideoPreview(controller: controller.videoController),
            const SizedBox(height: 18),
            _Panel(
              child: controller.hasTimeline
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '편집 타임라인',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            FilledButton.icon(
                              onPressed: controller.canRender
                                  ? context
                                        .read<EditorController>()
                                        .requestRender
                                  : null,
                              icon: const Icon(Icons.movie_creation_outlined),
                              label: Text(
                                controller.renderUrl == null
                                    ? '유튜브용 Export'
                                    : '다시 Export',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const EditControls(),
                        const SizedBox(height: 12),
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
                  : SizedBox(
                      height: 124,
                      child: Center(
                        child: Text(
                          controller.job?.stage == 'queued'
                              ? '분석 대기 중'
                              : '타임라인 대기 중',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }
}
