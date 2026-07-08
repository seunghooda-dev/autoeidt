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
      audioStart: 12,
      audioEnd: 22,
      audioMuted: true,
      audioVolume: 0.7,
      audioPan: -0.4,
      audioLinked: false,
      playbackSpeed: 1.5,
      audioFadeIn: 0.5,
      audioFadeOut: 1.0,
      score: 8.4,
      tags: ['핵심', '문제해결'],
    );

    final json = segment.toJson();
    expect(json['video_enabled'], isFalse);
    expect(json['audio_start'], 12);
    expect(json['audio_end'], 22);
    expect(json['audio_muted'], isTrue);
    expect(json['audio_volume'], 0.7);
    expect(json['audio_pan'], -0.4);
    expect(json['audio_linked'], isFalse);
    expect(json['playback_speed'], 1.5);
    expect(json['audio_fade_in'], 0.5);
    expect(json['audio_fade_out'], 1.0);
    expect(json['score'], 8.4);
    expect(json['tags'], ['핵심', '문제해결']);

    final restored = HighlightSegment.fromJson(json);
    expect(restored.videoEnabled, isFalse);
    expect(restored.effectiveAudioStart, 12);
    expect(restored.effectiveAudioEnd, 22);
    expect(restored.audioMuted, isTrue);
    expect(restored.audioVolume, 0.7);
    expect(restored.audioPan, -0.4);
    expect(restored.audioLinked, isFalse);
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
  });
}
