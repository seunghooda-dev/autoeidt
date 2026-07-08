import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_editor_app/models/highlight_segment.dart';
import 'package:highlight_editor_app/state/editor_controller.dart';
import 'package:highlight_editor_app/utils/timecode.dart';

void main() {
  test('highlight segment serializes audio track state', () {
    const segment = HighlightSegment(
      order: 1,
      start: 10,
      end: 20,
      reason: 'test',
      videoEnabled: false,
      videoFadeIn: 0.2,
      videoFadeOut: 0.4,
      colorBrightness: 0.1,
      colorContrast: 1.2,
      colorSaturation: 1.3,
      audioStart: 12,
      audioEnd: 22,
      audioMuted: true,
      audioVolume: 0.7,
      audioPan: -0.4,
      audioNormalize: true,
      audioLinked: false,
      audioChannel1Enabled: true,
      audioChannel2Enabled: false,
      playbackSpeed: 1.5,
      audioFadeIn: 0.5,
      audioFadeOut: 1.0,
      score: 8.4,
      tags: ['핵심', '문제해결'],
    );

    final json = segment.toJson();
    expect(json['video_enabled'], isFalse);
    expect(json['video_fade_in'], 0.2);
    expect(json['video_fade_out'], 0.4);
    expect(json['color_brightness'], 0.1);
    expect(json['color_contrast'], 1.2);
    expect(json['color_saturation'], 1.3);
    expect(json['audio_start'], 12);
    expect(json['audio_end'], 22);
    expect(json['audio_muted'], isTrue);
    expect(json['audio_volume'], 0.7);
    expect(json['audio_pan'], -0.4);
    expect(json['audio_normalize'], isTrue);
    expect(json['audio_linked'], isFalse);
    expect(json['audio_channel_1_enabled'], isTrue);
    expect(json['audio_channel_2_enabled'], isFalse);
    expect(json['playback_speed'], 1.5);
    expect(json['audio_fade_in'], 0.5);
    expect(json['audio_fade_out'], 1.0);
    expect(json['score'], 8.4);
    expect(json['tags'], ['핵심', '문제해결']);

    final restored = HighlightSegment.fromJson(json);
    expect(restored.videoEnabled, isFalse);
    expect(restored.videoFadeIn, 0.2);
    expect(restored.videoFadeOut, 0.4);
    expect(restored.colorBrightness, 0.1);
    expect(restored.colorContrast, 1.2);
    expect(restored.colorSaturation, 1.3);
    expect(restored.effectiveAudioStart, 12);
    expect(restored.effectiveAudioEnd, 22);
    expect(restored.audioMuted, isTrue);
    expect(restored.audioVolume, 0.7);
    expect(restored.audioPan, -0.4);
    expect(restored.audioNormalize, isTrue);
    expect(restored.audioLinked, isFalse);
    expect(restored.audioChannel1Enabled, isTrue);
    expect(restored.audioChannel2Enabled, isFalse);
    expect(restored.playbackSpeed, 1.5);
    expect(restored.audioFadeIn, 0.5);
    expect(restored.audioFadeOut, 1.0);
    expect(restored.score, 8.4);
    expect(restored.tags, ['핵심', '문제해결']);
    expect(restored.outputDuration, closeTo(6.666, 0.01));
  });

  test('linked audio follows video trim', () {
    final controller = EditorController(autoStartEngine: false)
      ..duration = 30
      ..segments = const [
        HighlightSegment(order: 1, start: 5, end: 12, reason: 'test'),
      ]
      ..selectedSegmentOrder = 1;

    controller.updateSegment(
      controller.segments.first.copyWith(start: 6, end: 14),
    );

    final selected = controller.selectedSegment!;
    expect(secondsToTimecodeFrame(selected.start), 180);
    expect(secondsToTimecodeFrame(selected.end), 420);
    expect(selected.effectiveAudioStart, selected.start);
    expect(selected.effectiveAudioEnd, selected.end);
    expect(selected.audioLinked, isTrue);
  });

  test('detached audio can move independently', () {
    final controller = EditorController(autoStartEngine: false)
      ..duration = 30
      ..segments = const [
        HighlightSegment(order: 1, start: 5, end: 12, reason: 'test'),
      ]
      ..selectedSegmentOrder = 1;

    controller.detachAudioForSelectedSegment();
    controller.nudgeSelectedAudioFrames(1);

    final selected = controller.selectedSegment!;
    expect(secondsToTimecodeFrame(selected.start), 150);
    expect(secondsToTimecodeFrame(selected.end), 360);
    expect(selected.effectiveAudioStart, timecodeFrameToSeconds(151));
    expect(selected.effectiveAudioEnd, timecodeFrameToSeconds(361));
    expect(selected.audioLinked, isFalse);
  });

  test('speed fade duplicate and undo redo update editor state', () {
    final controller = EditorController(autoStartEngine: false)
      ..duration = 30
      ..segments = const [
        HighlightSegment(order: 1, start: 5, end: 11, reason: 'test'),
      ]
      ..selectedSegmentOrder = 1;

    controller.setSelectedPlaybackSpeed(2);
    controller.setSelectedAudioFadeIn(0.5);
    controller.setSelectedAudioFadeOut(0.5);

    var selected = controller.selectedSegment!;
    expect(selected.playbackSpeed, 2);
    expect(selected.outputDuration, closeTo(3, 0.01));
    expect(selected.audioFadeIn, 0.5);
    expect(selected.audioFadeOut, 0.5);

    controller.duplicateSelectedSegment();
    expect(controller.segments.length, 2);
    expect(controller.selectedSegmentOrder, 2);

    controller.undo();
    expect(controller.segments.length, 1);
    expect(controller.selectedSegmentOrder, 1);

    controller.redo();
    expect(controller.segments.length, 2);
    expect(controller.selectedSegmentOrder, 2);
  });

  test('timeline context actions split at cursor and toggle audio link', () {
    final controller = EditorController(autoStartEngine: false)
      ..duration = 30
      ..segments = const [
        HighlightSegment(order: 1, start: 5, end: 13, reason: 'test'),
      ]
      ..selectedSegmentOrder = 1;

    controller.setMarkInAt(5.2);
    controller.setMarkOutAt(12.8);
    expect(secondsToTimecodeFrame(controller.markIn!), 156);
    expect(secondsToTimecodeFrame(controller.markOut!), 384);

    controller.splitSelectedAt(9);
    expect(controller.segments.length, 2);
    expect(secondsToTimecodeFrame(controller.segments.first.end), 270);
    expect(secondsToTimecodeFrame(controller.segments.last.start), 270);

    controller.toggleSelectedAudioLink();
    expect(controller.selectedSegment!.audioLinked, isFalse);
    controller.toggleSelectedAudioLink();
    expect(controller.selectedSegment!.audioLinked, isTrue);
  });

  test('premiere style cut shortcuts update timeline edits', () {
    final controller = EditorController(autoStartEngine: false)
      ..duration = 30
      ..segments = const [
        HighlightSegment(order: 1, start: 5, end: 13, reason: 'test'),
      ]
      ..selectedSegmentOrder = 1;

    controller.setRazorTool();
    expect(controller.isRazorTool, isTrue);
    expect(controller.timelineToolLabel, 'Razor C');

    controller.setSelectionTool();
    expect(controller.isRazorTool, isFalse);

    controller.rippleTrimSelectedStartTo(7);
    expect(secondsToTimecodeFrame(controller.selectedSegment!.start), 210);

    controller.rippleTrimSelectedEndTo(11);
    expect(secondsToTimecodeFrame(controller.selectedSegment!.end), 330);

    controller.extendSelectedStartTo(4);
    expect(secondsToTimecodeFrame(controller.selectedSegment!.start), 120);

    controller.extendSelectedEndTo(12);
    expect(secondsToTimecodeFrame(controller.selectedSegment!.end), 360);

    controller.markSelectedClip();
    expect(controller.markIn, controller.selectedSegment!.start);
    expect(controller.markOut, controller.selectedSegment!.end);

    controller.clearMarkIn();
    expect(controller.markIn, isNull);
    controller.clearMarkOut();
    expect(controller.markOut, isNull);

    controller.applyDefaultVideoTransition();
    controller.applyDefaultAudioTransition();
    expect(controller.selectedSegment!.videoFadeIn, 0.15);
    expect(controller.selectedSegment!.videoFadeOut, 0.15);
    expect(controller.selectedSegment!.audioFadeIn, 0.12);
    expect(controller.selectedSegment!.audioFadeOut, 0.12);

    controller.addEditAt(8);
    expect(controller.segments.length, 2);
    expect(secondsToTimecodeFrame(controller.segments.first.end), 240);
    expect(secondsToTimecodeFrame(controller.segments.last.start), 240);
  });

  test('video visibility audio pan and track locks update editor state', () {
    final controller = EditorController(autoStartEngine: false)
      ..duration = 30
      ..segments = const [
        HighlightSegment(order: 1, start: 5, end: 13, reason: 'test'),
        HighlightSegment(order: 2, start: 15, end: 20, reason: 'test 2'),
      ]
      ..selectedSegmentOrder = 1;

    controller.toggleSelectedVideoEnabled();
    expect(controller.selectedSegment!.videoEnabled, isFalse);

    controller.setSelectedAudioPan(1.5);
    expect(controller.selectedSegment!.audioPan, 1.0);

    controller.resetSelectedAudioPan();
    expect(controller.selectedSegment!.audioPan, 0);

    controller.setSelectedVideoFadeIn(20);
    controller.setSelectedVideoFadeOut(20);
    controller.setSelectedColorBrightness(1);
    controller.setSelectedColorContrast(5);
    controller.setSelectedColorSaturation(5);
    controller.toggleSelectedAudioNormalize();
    expect(controller.selectedSegment!.audioChannel1Enabled, isTrue);
    expect(controller.selectedSegment!.audioChannel2Enabled, isTrue);
    controller.toggleSelectedAudioChannel2();
    expect(controller.selectedSegment!.audioChannel1Enabled, isTrue);
    expect(controller.selectedSegment!.audioChannel2Enabled, isFalse);
    controller.toggleSelectedAudioChannel1();
    expect(controller.selectedSegment!.audioChannel1Enabled, isTrue);
    expect(controller.selectedSegment!.audioChannel2Enabled, isFalse);
    controller.toggleSelectedAudioChannel2();
    expect(controller.selectedSegment!.audioChannel2Enabled, isTrue);
    var selected = controller.selectedSegment!;
    expect(selected.videoFadeIn, closeTo(4, 0.01));
    expect(selected.videoFadeOut, closeTo(4, 0.01));
    expect(selected.colorBrightness, 0.3);
    expect(selected.colorContrast, 1.8);
    expect(selected.colorSaturation, 2.0);
    expect(selected.audioNormalize, isTrue);

    controller.resetSelectedColor();
    selected = controller.selectedSegment!;
    expect(selected.colorBrightness, 0);
    expect(selected.colorContrast, 1);
    expect(selected.colorSaturation, 1);

    controller.toggleAllAudioMute();
    expect(controller.segments.every((segment) => segment.audioMuted), isTrue);

    controller.toggleVideoTrackLock();
    controller.toggleSelectedVideoEnabled();
    expect(controller.selectedSegment!.videoEnabled, isFalse);

    controller.toggleAudioTrackLock();
    controller.toggleAllAudioMute();
    expect(controller.segments.every((segment) => segment.audioMuted), isTrue);
  });

  test('ai director condenses weak clips and applies shorts preset', () {
    final controller = EditorController(autoStartEngine: false)
      ..duration = 120
      ..segments = const [
        HighlightSegment(
          order: 1,
          start: 0,
          end: 20,
          reason: 'low',
          score: 2,
          tags: ['CTA'],
        ),
        HighlightSegment(
          order: 2,
          start: 20,
          end: 45,
          reason: 'high',
          score: 9,
          tags: ['핵심'],
        ),
        HighlightSegment(
          order: 3,
          start: 45,
          end: 75,
          reason: 'medium',
          score: 6,
          tags: ['문제해결'],
        ),
      ]
      ..captions = const [
        CaptionSegment(order: 1, start: 0, end: 2, text: '음 이제 시작합니다'),
        CaptionSegment(order: 2, start: 20, end: 22, text: '핵심 내용입니다'),
      ]
      ..selectedSegmentOrder = 2;

    expect(controller.weakClipCount, 1);
    expect(controller.fillerCaptionCount, 1);

    controller.removeWeakSegments();
    expect(controller.segments.length, 2);
    expect(controller.segments.any((segment) => segment.score == 2), isFalse);

    controller.hideFillerCaptions();
    expect(controller.captions.first.enabled, isFalse);
    expect(controller.captions.last.enabled, isTrue);

    controller.applyShortsDirectorPreset();
    expect(controller.exportAspectRatio, '9:16');
    expect(controller.includeCaptions, isTrue);
    expect(
      controller.segments.every(
        (segment) => segment.source.contains('director'),
      ),
      isTrue,
    );

    controller.applyFinishingPreset();
    expect(controller.includeCaptions, isTrue);
    expect(
      controller.segments.every((segment) => segment.audioNormalize),
      isTrue,
    );
    expect(
      controller.segments.every((segment) => segment.videoFadeIn > 0),
      isTrue,
    );
    expect(
      controller.segments.every((segment) => segment.colorContrast >= 1),
      isTrue,
    );
  });

  test('director comparison caption audio and QA passes update timeline', () {
    final controller = EditorController(autoStartEngine: false)
      ..duration = 300
      ..segments = const [
        HighlightSegment(
          order: 1,
          start: 0,
          end: 80,
          reason: '결과부터 보여주는 핵심 구간',
          script: '결과부터 보여드리면 중요한 근거가 있습니다',
          score: 9,
          tags: ['뉴스핵심', '근거'],
        ),
        HighlightSegment(
          order: 2,
          start: 120,
          end: 150,
          reason: '미확인 루머 언급',
          script: '아직 확인되지 않은 루머가 있습니다',
          score: 5,
          tags: ['미확인'],
        ),
      ]
      ..captions = const [
        CaptionSegment(order: 1, start: 0, end: 3, text: '음 이제 시작합니다'),
        CaptionSegment(order: 2, start: 120, end: 123, text: '미확인 루머입니다'),
      ]
      ..selectedSegmentOrder = 1;

    expect(controller.editorialBlockCount, 1);
    expect(controller.editorialWarnCount, greaterThanOrEqualTo(1));

    controller.buildAiComparisonVariants();
    expect(controller.hasComparisonVariants, isTrue);
    expect(controller.comparisonReferenceSegments.first.duration <= 52, isTrue);

    controller.applyComparisonVariant('reference');
    expect(controller.segments.first.source.contains('reference'), isTrue);

    controller.applyCaptionStylePreset('shorts');
    expect(controller.captionStylePreset, 'shorts');
    expect(controller.includeCaptions, isTrue);
    expect(controller.captionRenderStyle.fontSize, 36);

    controller.applyAudioAutoMix();
    expect(
      controller.segments
          .where((segment) => !segment.audioMuted)
          .every((segment) => segment.audioNormalize && segment.audioPan == 0),
      isTrue,
    );

    controller.applyEditorialReviewPass();
    expect(controller.captions.first.enabled, isFalse);
    expect(controller.includeCaptions, isTrue);
    expect(
      controller.segments.every((segment) => segment.audioFadeOut > 0),
      isTrue,
    );
  });

  test('auto fix queue detects and repairs common edit issues', () {
    final controller = EditorController(autoStartEngine: false)
      ..duration = 180
      ..segments = const [
        HighlightSegment(
          order: 1,
          start: 10,
          end: 11.4,
          reason: 'too short',
          videoEnabled: false,
          audioMuted: true,
          score: 8,
        ),
        HighlightSegment(
          order: 2,
          start: 20,
          end: 95,
          reason: 'too long',
          audioNormalize: false,
          score: 7,
        ),
        HighlightSegment(
          order: 3,
          start: 120,
          end: 132,
          reason: 'weak',
          script: '음 이제 반복 멘트입니다',
          score: 2,
        ),
      ]
      ..captions = const [
        CaptionSegment(order: 1, start: 120, end: 123, text: '음 이제 반복입니다'),
      ]
      ..selectedSegmentOrder = 1;

    expect(controller.autoFixCount, greaterThan(0));
    expect(
      controller.autoFixQueue.any(
        (item) => item.action == AutoFixAction.restoreVideo,
      ),
      isTrue,
    );
    expect(
      controller.autoFixQueue.any(
        (item) => item.action == AutoFixAction.trimLongClip,
      ),
      isTrue,
    );

    controller.applyAutoFixForSegment(1, AutoFixAction.restoreVideo);
    expect(controller.segments.first.videoEnabled, isTrue);

    controller.applyAllAutoFixes();
    expect(controller.segments.any((segment) => segment.score == 2), isFalse);
    expect(
      controller.segments.every((segment) => segment.videoEnabled),
      isTrue,
    );
    expect(controller.segments.every((segment) => !segment.audioMuted), isTrue);
    expect(
      controller.segments.every((segment) => segment.audioNormalize),
      isTrue,
    );
    expect(
      controller.segments.every((segment) => segment.duration <= 70),
      isTrue,
    );
    expect(
      controller.autoFixQueue.any(
        (item) => item.severity == AutoFixSeverity.block,
      ),
      isFalse,
    );
  });

  test('multi shorts candidates can be built edited and selected', () {
    final controller = EditorController(autoStartEngine: false)
      ..duration = 1800
      ..segments = const [
        HighlightSegment(
          order: 1,
          start: 10,
          end: 70,
          reason: 'hook',
          score: 9,
          tags: ['유지율'],
        ),
        HighlightSegment(
          order: 2,
          start: 80,
          end: 135,
          reason: 'evidence',
          score: 8,
          tags: ['근거'],
        ),
        HighlightSegment(
          order: 3,
          start: 180,
          end: 240,
          reason: 'impact',
          score: 7,
          tags: ['영향'],
        ),
        HighlightSegment(
          order: 4,
          start: 360,
          end: 410,
          reason: 'weak',
          score: 3,
          tags: ['CTA'],
        ),
      ]
      ..selectedSegmentOrder = 1;

    controller.buildMultiShortsCandidates(maxCandidates: 3);
    expect(controller.hasShortsCandidates, isTrue);
    expect(controller.selectedShortsCandidate, isNotNull);
    expect(controller.exportAspectRatio, '9:16');
    expect(controller.captionStylePreset, 'shorts');
    expect(
      controller.shortsCandidates.every(
        (candidate) => candidate.qualityScore >= 0,
      ),
      isTrue,
    );
    expect(controller.shortsCandidates.first.qualityGrade, isNotEmpty);
    expect(
      controller.shortsCandidates.first.qualityScore,
      greaterThanOrEqualTo(controller.shortsCandidates.last.qualityScore),
    );
    expect(
      controller.shortsCandidates.first.strengths.isNotEmpty ||
          controller.shortsCandidates.first.issues.isNotEmpty,
      isTrue,
    );

    final selectedId = controller.selectedShortsId!;
    controller.updateSegment(controller.segments.first.copyWith(end: 60));
    controller.updateSelectedShortsFromTimeline();
    final updatedCandidate = controller.shortsCandidates.firstWhere(
      (candidate) => candidate.id == selectedId,
    );
    expect(updatedCandidate.segments.first.end, closeTo(60, 0.01));
    expect(updatedCandidate.qualityScore, greaterThan(0));

    controller.duplicateShortsCandidate(selectedId);
    expect(controller.shortsCandidates.length, greaterThan(1));
    expect(controller.shortsCandidates.last.qualityScore, greaterThan(0));

    controller.toggleShortsCandidate(selectedId);
    expect(
      controller.shortsCandidates
          .firstWhere((candidate) => candidate.id == selectedId)
          .selected,
      isFalse,
    );

    controller.deleteShortsCandidate(selectedId);
    expect(
      controller.shortsCandidates.any(
        (candidate) => candidate.id == selectedId,
      ),
      isFalse,
    );
  });
}
