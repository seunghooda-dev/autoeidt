import 'dart:convert';
import 'dart:io' as io;

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_editor_app/models/highlight_segment.dart';
import 'package:highlight_editor_app/models/job_models.dart';
import 'package:highlight_editor_app/services/api_client.dart';
import 'package:highlight_editor_app/services/local_engine_service.dart';
import 'package:highlight_editor_app/services/project_recovery_service.dart';
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
      focusX: 0.72,
      focusY: 0.31,
      focusConfidence: 0.84,
      focusKeyframes: [
        ReframeKeyframe(time: 0, x: 0.72, y: 0.31),
        ReframeKeyframe(time: 4, x: 0.84, y: 0.34),
      ],
      topicId: 3,
      audioStart: 12,
      audioEnd: 22,
      audioMuted: true,
      audioVolume: 0.7,
      audioPan: -0.4,
      audioNormalize: true,
      audioLoudnessTarget: -24,
      audioLinked: false,
      audioChannel1Enabled: true,
      audioChannel2Enabled: false,
      audioSourceChannelLeft: 7,
      audioSourceChannelRight: 8,
      playbackSpeed: 1.5,
      transitionType: 'dip_black',
      transitionDuration: 0.6,
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
    expect(json['focus_x'], 0.72);
    expect(json['focus_y'], 0.31);
    expect(json['focus_confidence'], 0.84);
    expect((json['focus_keyframes'] as List).length, 2);
    expect(json['topic_id'], 3);
    expect(json['audio_start'], 12);
    expect(json['audio_end'], 22);
    expect(json['audio_muted'], isTrue);
    expect(json['audio_volume'], 0.7);
    expect(json['audio_pan'], -0.4);
    expect(json['audio_normalize'], isTrue);
    expect(json['audio_loudness_target'], -24);
    expect(json['audio_linked'], isFalse);
    expect(json['audio_channel_1_enabled'], isTrue);
    expect(json['audio_channel_2_enabled'], isFalse);
    expect(json['audio_source_channel_left'], 7);
    expect(json['audio_source_channel_right'], 8);
    expect(json['playback_speed'], 1.5);
    expect(json['transition_type'], 'dip_black');
    expect(json['transition_duration'], 0.6);
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
    expect(restored.focusX, 0.72);
    expect(restored.focusY, 0.31);
    expect(restored.focusConfidence, 0.84);
    expect(restored.focusKeyframes.length, 2);
    expect(restored.focusKeyframes.last.x, 0.84);
    expect(restored.topicId, 3);
    expect(restored.effectiveAudioStart, 12);
    expect(restored.effectiveAudioEnd, 22);
    expect(restored.audioMuted, isTrue);
    expect(restored.audioVolume, 0.7);
    expect(restored.audioPan, -0.4);
    expect(restored.audioNormalize, isTrue);
    expect(restored.audioLoudnessTarget, -24);
    expect(restored.audioLinked, isFalse);
    expect(restored.audioChannel1Enabled, isTrue);
    expect(restored.audioChannel2Enabled, isFalse);
    expect(restored.audioSourceChannelLeft, 7);
    expect(restored.audioSourceChannelRight, 8);
    expect(restored.playbackSpeed, 1.5);
    expect(restored.transitionType, 'dip_black');
    expect(restored.transitionDuration, 0.6);
    expect(restored.audioFadeIn, 0.5);
    expect(restored.audioFadeOut, 1.0);
    expect(restored.score, 8.4);
    expect(restored.tags, ['핵심', '문제해결']);
    expect(restored.outputDuration, closeTo(6.666, 0.01));
  });

  test('selected clip routes broadcast source channels to stereo output', () {
    final controller = EditorController(autoStartEngine: false)
      ..selectedMediaProbe = MediaProbeInfo.fromJson({
        'audio_stream_count': 1,
        'audio_channel_count': 8,
      })
      ..segments = const [
        HighlightSegment(order: 1, start: 0, end: 10, reason: 'routing'),
      ]
      ..selectedSegmentOrder = 1;

    controller.setSelectedAudioSourceChannelLeft(7);
    controller.setSelectedAudioSourceChannelRight(8);
    expect(controller.selectedSegment!.audioSourceChannelLeft, 7);
    expect(controller.selectedSegment!.audioSourceChannelRight, 8);
    controller.setSelectedAudioSourceChannelRight(99);
    expect(controller.selectedSegment!.audioSourceChannelRight, 8);
    controller.setSelectedAudioLoudnessTarget(-24);
    expect(controller.selectedSegment!.audioNormalize, isTrue);
    expect(controller.selectedSegment!.audioLoudnessTarget, -24);
    controller.dispose();
  });

  test('project state preserves render settings and marks', () {
    const project = ProjectState(
      name: 'Shorts Project',
      duration: 120,
      segments: [],
      transcript: [
        TranscriptSegment(start: 10.5, end: 14.2, text: '보존되어야 하는 전체 STT 원문'),
      ],
      captions: [],
      waveform: [],
      timelineMarkers: [
        TimelineMarker(
          id: 1,
          seconds: 12.5,
          label: 'Hook',
          color: 'cyan',
          note: 'opening marker',
          enabled: false,
        ),
      ],
      includeCaptions: false,
      captionStylePreset: 'shorts',
      exportAspectRatio: '9:16',
      selectedExportProfiles: ['16:9', '9:16'],
      markIn: 10.5,
      markOut: 88.0,
      originalFilename: 'source.mxf',
      originalPath: r'C:\media\source.mxf',
      shortsCandidates: [
        {
          'id': 3,
          'label': 'News 03',
          'reason': 'stored candidate',
          'segments': [
            {
              'order': 1,
              'start': 12.0,
              'end': 42.0,
              'reason': 'hook',
              'score': 8.0,
              'tags': ['뉴스핵심'],
            },
          ],
          'quality_score': 88.0,
          'hook_score': 91.0,
          'completion_score': 76.0,
          'story_flow': ['Hook', 'Evidence'],
          'selected': true,
        },
      ],
      selectedShortsId: 3,
    );

    final restored = ProjectState.fromJson(project.toJson());
    final restoredFromLegacyDropFrame = ProjectState.fromJson({
      ...project.toJson(),
      'timeline_frame_rate': 29.97,
      'timeline_timecode_mode': 'drop',
    });

    expect(project.toJson()['timeline_frame_rate'], 30.0);
    expect(project.toJson()['timeline_timecode_mode'], 'non_drop');
    expect(restored.timelineFrameRate, 30.0);
    expect(restored.timelineTimecodeMode, 'non_drop');
    expect(restoredFromLegacyDropFrame.timelineFrameRate, 30.0);
    expect(restoredFromLegacyDropFrame.timelineTimecodeMode, 'non_drop');
    expect(restored.includeCaptions, isFalse);
    expect(restored.captionStylePreset, 'shorts');
    expect(restored.exportAspectRatio, '9:16');
    expect(restored.selectedExportProfiles, ['16:9', '9:16']);
    expect(restored.transcript.single.text, '보존되어야 하는 전체 STT 원문');
    expect(restored.transcript.single.start, 10.5);
    expect(restored.markIn, 10.5);
    expect(restored.markOut, 88.0);
    expect(restored.originalFilename, 'source.mxf');
    expect(restored.originalPath, r'C:\media\source.mxf');
    expect(restored.timelineMarkers.single.label, 'Hook');
    expect(restored.timelineMarkers.single.seconds, 12.5);
    expect(restored.timelineMarkers.single.note, 'opening marker');
    expect(restored.timelineMarkers.single.enabled, isFalse);
    expect(restored.shortsCandidates.single['label'], 'News 03');
    expect(restored.shortsCandidates.single['quality_score'], 88.0);
    expect(restored.shortsCandidates.single['hook_score'], 91.0);
    expect(restored.shortsCandidates.single['completion_score'], 76.0);
    expect(restored.selectedShortsId, 3);
  });

  test('project file saves and reopens without losing editor data', () async {
    final directory = await io.Directory.systemTemp.createTemp(
      'autoedit_project_file_test',
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });
    final projectPath =
        '${directory.path}${io.Platform.pathSeparator}news.autoedit.json';
    final controller = EditorController(autoStartEngine: false)
      ..projectName = 'Evening News'
      ..duration = 120
      ..segments = const [
        HighlightSegment(order: 1, start: 10, end: 30, reason: 'lead'),
      ]
      ..selectedSegmentOrder = 1
      ..transcript = const [
        TranscriptSegment(start: 10, end: 15, text: '뉴스 리드 원문'),
        TranscriptSegment(start: 15, end: 22, text: '취재 근거 원문'),
      ]
      ..selectedExportProfiles = const ['16:9', '9:16']
      ..exportAspectRatio = '16:9';

    controller.updateSegment(
      controller.segments.single.copyWith(reason: 'verified lead'),
    );
    expect(controller.hasUnsavedProjectChanges, isTrue);

    await controller.saveProjectToPath(projectPath);
    expect(controller.projectFilePath, projectPath);
    expect(controller.projectFileLabel, 'news.autoedit.json');
    expect(controller.hasUnsavedProjectChanges, isFalse);

    final firstPayload =
        jsonDecode(await io.File(projectPath).readAsString())
            as Map<String, dynamic>;
    expect(firstPayload['version'], 2);
    expect(firstPayload['transcript'], hasLength(2));
    expect(firstPayload['selected_export_profiles'], ['16:9', '9:16']);

    controller.setExportProfiles({'9:16', '1:1'});
    expect(controller.hasUnsavedProjectChanges, isTrue);
    await controller.saveProjectFile();
    expect(controller.hasUnsavedProjectChanges, isFalse);

    final reopened = EditorController(autoStartEngine: false);
    await reopened.openProjectPath(projectPath, initializePreview: false);
    expect(reopened.projectName, 'Evening News');
    expect(reopened.projectFilePath, projectPath);
    expect(reopened.hasUnsavedProjectChanges, isFalse);
    expect(reopened.transcript.map((item) => item.text), [
      '뉴스 리드 원문',
      '취재 근거 원문',
    ]);
    expect(reopened.selectedExportProfiles, ['9:16', '1:1']);
    expect(reopened.exportAspectRatio, '9:16');
    expect(reopened.segments.single.reason, 'verified lead');

    controller.dispose();
    reopened.dispose();
  });

  test(
    'project recovery service writes restores and clears snapshots',
    () async {
      final directory = await io.Directory.systemTemp.createTemp(
        'autoedit_recovery_service_test',
      );
      addTearDown(() async {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      });

      final service = ProjectRecoveryService(
        directory: directory,
        clock: () => DateTime.utc(2026, 1, 2, 3, 4, 5),
      );
      const project = ProjectState(
        name: 'Recovered News Cut',
        duration: 120,
        segments: [
          HighlightSegment(order: 1, start: 10, end: 42, reason: 'hook'),
        ],
        captions: [],
        waveform: [0.1, 0.4],
        markIn: 10,
        markOut: 42,
      );

      final saved = await service.saveProject(project);
      expect(saved.savedAt, DateTime.utc(2026, 1, 2, 3, 4, 5));
      expect(saved.label, 'Auto Save');
      expect(saved.isManual, isFalse);
      expect(await service.hasSnapshot(), isTrue);
      expect(await service.listVersions(), hasLength(1));

      final snapshot = await service.readSnapshot();
      expect(snapshot, isNotNull);
      expect(snapshot!.project.name, 'Recovered News Cut');
      expect(snapshot.project.segments.single.end, 42);
      expect(snapshot.project.markIn, 10);

      final manualProject = ProjectState(
        name: project.name,
        duration: project.duration,
        segments: const [
          HighlightSegment(
            order: 1,
            start: 10,
            end: 55,
            reason: 'extended hook',
          ),
        ],
        captions: project.captions,
        waveform: project.waveform,
        markIn: project.markIn,
        markOut: 55,
      );
      final manual = await service.saveProject(
        manualProject,
        label: 'Before final export',
        manual: true,
      );
      final versions = await service.listVersions();
      expect(versions, hasLength(2));
      expect(versions.first.id, manual.id);
      expect(versions.first.label, 'Before final export');
      expect(versions.first.isManual, isTrue);

      final selectedVersion = await service.readVersion(manual.id);
      expect(selectedVersion, isNotNull);
      expect(selectedVersion!.project.segments.single.end, 55);

      await service.deleteVersion(saved.id);
      expect(await service.listVersions(), hasLength(1));

      await service.clearSnapshot();
      expect(await service.hasSnapshot(), isFalse);
      expect(await service.listVersions(), isEmpty);
    },
  );

  test(
    'project recovery retains twenty autosaves without pruning snapshots',
    () async {
      final directory = await io.Directory.systemTemp.createTemp(
        'autoedit_recovery_rotation_test',
      );
      addTearDown(() async {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      });

      var tick = 0;
      final service = ProjectRecoveryService(
        directory: directory,
        clock: () => DateTime.utc(2026, 1, 2).add(Duration(seconds: tick++)),
      );
      await service.saveProject(
        const ProjectState(
          name: 'Pinned manual version',
          duration: 120,
          segments: [],
          captions: [],
          waveform: [],
        ),
        label: 'Pinned manual version',
        manual: true,
      );
      for (var index = 0; index < 23; index += 1) {
        await service.saveProject(
          ProjectState(
            name: 'Version $index',
            duration: 120,
            segments: [
              HighlightSegment(
                order: 1,
                start: index.toDouble(),
                end: index + 10.0,
                reason: 'version $index',
              ),
            ],
            captions: const [],
            waveform: const [],
          ),
        );
      }

      final versions = await service.listVersions();
      final automatic = versions.where((version) => !version.isManual).toList();
      expect(automatic, hasLength(20));
      expect(automatic.first.project.name, 'Version 22');
      expect(automatic.last.project.name, 'Version 3');
      expect(
        versions.where((version) => version.isManual).single.label,
        'Pinned manual version',
      );
    },
  );

  test('editor controller autosaves and restores recovery snapshot', () async {
    final directory = await io.Directory.systemTemp.createTemp(
      'autoedit_controller_recovery_test',
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    final service = ProjectRecoveryService(
      directory: directory,
      clock: () => DateTime.utc(2026, 1, 2, 3, 4, 5),
    );
    final sourcePath =
        '${directory.path}${io.Platform.pathSeparator}source.mp4';
    await io.File(sourcePath).writeAsBytes([0, 1, 2]);
    final controller =
        EditorController(
            autoStartEngine: false,
            recoveryService: service,
            enableProjectRecovery: true,
            projectRecoveryDebounce: const Duration(milliseconds: 10),
          )
          ..projectName = 'Autosaved Timeline'
          ..selectedFile = PlatformFile(
            name: 'source.mp4',
            size: 123,
            path: sourcePath,
          )
          ..duration = 180
          ..segments = const [
            HighlightSegment(order: 1, start: 30, end: 60, reason: 'first cut'),
          ]
          ..selectedSegmentOrder = 1
          ..markIn = 30
          ..markOut = 60;

    controller.updateSegment(controller.segments.first.copyWith(end: 75));

    final snapshot = await _waitForRecoverySnapshot(service);
    expect(snapshot, isNotNull);
    expect(snapshot!.project.name, 'Autosaved Timeline');
    expect(snapshot.project.originalFilename, 'source.mp4');
    expect(snapshot.project.originalPath, controller.selectedFile!.path);
    expect(snapshot.project.segments.single.end, 75);
    expect(snapshot.project.markOut, 60);

    final restored = EditorController(
      autoStartEngine: false,
      recoveryService: service,
      enableProjectRecovery: true,
      projectRecoveryDebounce: const Duration(milliseconds: 10),
    );
    await restored.restoreRecoveryProject(initializePreview: false);

    expect(restored.hasRecoverySnapshot, isTrue);
    expect(restored.projectName, 'Autosaved Timeline');
    expect(restored.selectedFile?.name, 'source.mp4');
    expect(restored.selectedFile?.path, sourcePath);
    expect(restored.sourceMediaIsLinked, isTrue);
    expect(restored.sourceMediaNeedsRelink, isFalse);
    expect(restored.duration, 180);
    expect(restored.segments.single.end, 75);
    expect(restored.markIn, 30);

    await restored.createManualRecoverySnapshot(label: 'Approved rough cut');
    final manual = restored.recoveryVersions.first;
    expect(manual.label, 'Approved rough cut');
    expect(manual.isManual, isTrue);

    restored.updateSegment(restored.segments.single.copyWith(end: 90));
    expect(restored.segments.single.end, 90);
    await restored.restoreRecoveryVersion(manual.id, initializePreview: false);
    expect(restored.segments.single.end, 75);

    await restored.deleteRecoveryVersion(manual.id);
    expect(
      restored.recoveryVersions.any((version) => version.id == manual.id),
      isFalse,
    );

    controller.dispose();
    restored.dispose();
  });

  test('editor project state captures current render settings', () {
    final controller = EditorController(autoStartEngine: false)
      ..selectedFile = PlatformFile(
        name: 'news_source.mxf',
        size: 1024,
        path: r'C:\media\news_source.mxf',
      )
      ..duration = 120
      ..includeCaptions = false
      ..captionStylePreset = 'shorts'
      ..exportAspectRatio = '9:16'
      ..markIn = 10.5
      ..markOut = 88.0
      ..timelineMarkers = const [
        TimelineMarker(
          id: 1,
          seconds: 14,
          label: 'Fact',
          color: 'green',
          enabled: false,
        ),
      ]
      ..shortsCandidates = const [
        ShortsCandidate(
          id: 4,
          label: 'Hook 04',
          reason: 'saved hook',
          segments: [
            HighlightSegment(
              order: 1,
              start: 8,
              end: 38,
              reason: 'hook',
              score: 8,
              tags: ['후킹'],
            ),
          ],
          strategyKind: 'hook',
          strategyLabel: 'Hook',
          qualityScore: 81,
          qualityGrade: 'A',
          storyFlow: ['Hook'],
          storyScore: 70,
          selected: true,
        ),
      ]
      ..selectedShortsId = 4;

    final project = controller.projectState;

    expect(project.includeCaptions, isFalse);
    expect(project.timelineFrameRate, 30.0);
    expect(project.timelineTimecodeMode, 'non_drop');
    expect(project.captionStylePreset, 'shorts');
    expect(project.exportAspectRatio, '9:16');
    expect(project.markIn, 10.5);
    expect(project.markOut, 88.0);
    expect(project.originalFilename, 'news_source.mxf');
    expect(project.originalPath, r'C:\media\news_source.mxf');
    expect(project.timelineMarkers.single.label, 'Fact');
    expect(project.timelineMarkers.single.color, 'green');
    expect(project.timelineMarkers.single.enabled, isFalse);
    expect(project.shortsCandidates.single['id'], 4);
    expect(project.shortsCandidates.single['strategy_kind'], 'hook');
    expect(project.shortsCandidates.single['hook_score'], 0);
    expect(project.shortsCandidates.single['completion_score'], 0);
    expect(project.selectedShortsId, 4);
  });

  test('backend project save includes shorts candidates', () async {
    final apiClient = _RecordingApiClient();
    final controller =
        EditorController(apiClient: apiClient, autoStartEngine: false)
          ..jobId = 'job-1'
          ..duration = 120
          ..timelineMarkers = const [
            TimelineMarker(
              id: 2,
              seconds: 30,
              label: 'Review',
              color: 'rose',
              enabled: false,
            ),
          ]
          ..shortsCandidates = const [
            ShortsCandidate(
              id: 7,
              label: 'News 07',
              reason: 'persist me',
              segments: [
                HighlightSegment(
                  order: 1,
                  start: 20,
                  end: 80,
                  reason: 'impact',
                  score: 9,
                  tags: ['뉴스핵심'],
                ),
              ],
              strategyKind: 'news',
              strategyLabel: 'News',
              qualityScore: 86,
              qualityGrade: 'A',
              storyFlow: ['Hook', 'Impact'],
              storyScore: 72,
            ),
          ]
          ..selectedShortsId = 7;

    await controller.saveProjectToBackend();

    expect(apiClient.savedProjectJobId, 'job-1');
    expect(apiClient.savedProject?.timelineMarkers.single.label, 'Review');
    expect(apiClient.savedProject?.timelineMarkers.single.enabled, isFalse);
    expect(apiClient.savedProject?.shortsCandidates.single['id'], 7);
    expect(apiClient.savedProject?.shortsCandidates.single['label'], 'News 07');
    expect(apiClient.savedProject?.shortsCandidates.single['hook_score'], 0);
    expect(
      apiClient.savedProject?.shortsCandidates.single['completion_score'],
      0,
    );
    expect(apiClient.savedProject?.selectedShortsId, 7);
    expect(controller.shortsCandidates.single.label, 'News 07');
    expect(controller.selectedShortsId, 7);
  });

  test('selected shorts cut list csv exports editorial source ranges', () {
    final controller = EditorController(autoStartEngine: false)
      ..shortsCandidates = const [
        ShortsCandidate(
          id: 1,
          label: 'News, 01',
          reason: 'selected',
          strategyKind: 'news',
          strategyLabel: 'News',
          selected: true,
          qualityScore: 82,
          qualityGrade: 'A',
          hookScore: 76,
          completionScore: 68,
          storyScore: 72,
          storyFlow: ['Hook', 'Evidence'],
          strengths: ['Story'],
          issues: ['Missing impact'],
          segments: [
            HighlightSegment(
              order: 2,
              start: 1,
              end: 2.5,
              reason: '공식 보고서, 확인',
              script: '관계자는 "확인"했다고 말했습니다',
              tags: ['Story:Evidence', '검증팩트'],
              audioStart: 1.2,
              audioEnd: 2.4,
              audioChannel2Enabled: false,
              playbackSpeed: 1.25,
            ),
          ],
        ),
        ShortsCandidate(
          id: 2,
          label: 'Skip 02',
          reason: 'not selected',
          selected: false,
          segments: [
            HighlightSegment(order: 1, start: 10, end: 12, reason: 'skip'),
          ],
        ),
      ];

    final csv = controller.buildSelectedShortsCutListCsv();

    expect(csv, contains('candidate_id,candidate_label,selected'));
    expect(csv, contains('"News, 01"'));
    expect(csv, contains('00:00:01:00'));
    expect(csv, contains('00:00:02:15'));
    expect(csv, contains('"관계자는 ""확인""했다고 말했습니다"'));
    expect(csv, contains('Evidence'));
    expect(csv, isNot(contains('Skip 02')));
  });

  test('timeline markers can be added navigated cleared and undone', () async {
    final controller = EditorController(autoStartEngine: false)..duration = 120;

    controller.addTimelineMarkerAt(12.345, label: 'Hook');

    expect(controller.timelineMarkers.length, 1);
    expect(
      secondsToTimecodeFrame(controller.timelineMarkers.single.seconds),
      370,
    );
    expect(controller.timelineMarkers.single.label, 'Hook');

    controller.addTimelineMarkerAt(35, label: 'Fact');
    expect(controller.timelineMarkers.map((marker) => marker.label), [
      'Hook',
      'Fact',
    ]);
    final firstMarkerId = controller.timelineMarkers.first.id;
    final firstMarkerSeconds = controller.timelineMarkers.first.seconds;
    final secondMarkerSeconds = controller.timelineMarkers.last.seconds;
    expect(controller.canJumpToNextTimelineMarker, isTrue);
    expect(controller.canJumpToPreviousTimelineMarker, isFalse);

    controller.jumpToNextTimelineMarker();
    await Future<void>.delayed(Duration.zero);
    expect(
      controller.currentPositionSeconds,
      controller.timelineMarkers.first.seconds,
    );

    controller.jumpToNextTimelineMarker();
    await Future<void>.delayed(Duration.zero);
    expect(
      controller.currentPositionSeconds,
      controller.timelineMarkers.last.seconds,
    );
    expect(controller.canJumpToNextTimelineMarker, isFalse);
    expect(controller.canJumpToPreviousTimelineMarker, isTrue);

    controller.jumpToPreviousTimelineMarker();
    await Future<void>.delayed(Duration.zero);
    expect(
      controller.currentPositionSeconds,
      controller.timelineMarkers.first.seconds,
    );

    controller.setMarksFromTimelineMarker(firstMarkerId);
    await Future<void>.delayed(Duration.zero);
    expect(controller.markIn, firstMarkerSeconds);
    expect(controller.markOut, secondMarkerSeconds);

    controller.addSegmentFromTimelineMarker(firstMarkerId);
    await Future<void>.delayed(Duration.zero);
    expect(controller.segments.single.reason, '마커 Hook 구간');
    expect(controller.segments.single.start, firstMarkerSeconds);
    expect(controller.segments.single.end, secondMarkerSeconds);
    expect(controller.segments.single.tags, ['marker']);

    controller.replaceTimelineWithMarkerSegments();
    await Future<void>.delayed(Duration.zero);
    expect(controller.segments.length, 2);
    expect(controller.segments.first.reason, '마커 Hook 구간');
    expect(controller.segments.last.reason, '마커 Fact 구간');
    expect(controller.segments.first.start, firstMarkerSeconds);
    expect(controller.segments.first.end, secondMarkerSeconds);
    expect(controller.selectedSegmentOrder, 1);

    controller.undo();
    expect(controller.segments.length, 1);

    controller.deleteTimelineMarker(firstMarkerId);
    expect(controller.timelineMarkers.single.label, 'Fact');

    controller.undo();
    expect(controller.timelineMarkers.length, 2);

    controller.updateTimelineMarker(
      controller.timelineMarkers.first.copyWith(
        label: 'Edited',
        note: 'review point',
        color: 'violet',
      ),
    );
    expect(controller.timelineMarkers.first.label, 'Edited');
    expect(controller.timelineMarkers.first.note, 'review point');
    expect(controller.timelineMarkers.first.color, 'violet');

    controller.undo();
    expect(controller.timelineMarkers.first.label, 'Hook');

    controller.clearTimelineMarkers();
    expect(controller.timelineMarkers, isEmpty);

    controller.undo();
    expect(controller.timelineMarkers.length, 2);
  });

  test('playhead navigation snaps to 30p frames and edit points', () async {
    final controller = EditorController(autoStartEngine: false)
      ..duration = 120
      ..segments = const [
        HighlightSegment(order: 1, start: 10, end: 20, reason: 'a'),
        HighlightSegment(order: 2, start: 35, end: 50, reason: 'b'),
      ]
      ..selectedSegmentOrder = 1;

    await controller.seekTo(10, autoplay: false);
    await controller.stepPlayheadByFrames(1);
    expect(secondsToTimecodeFrame(controller.currentPositionSeconds), 301);

    await controller.stepPlayheadByFrames(-10);
    expect(secondsToTimecodeFrame(controller.currentPositionSeconds), 291);

    await controller.jumpToNextEditPoint();
    expect(secondsToTimecodeFrame(controller.currentPositionSeconds), 300);

    await controller.jumpToNextEditPoint();
    expect(secondsToTimecodeFrame(controller.currentPositionSeconds), 600);

    await controller.jumpToPreviousEditPoint();
    expect(secondsToTimecodeFrame(controller.currentPositionSeconds), 300);

    controller.setMarkInAt(35);
    controller.setMarkOutAt(50);
    await controller.jumpToMarkOut();
    expect(secondsToTimecodeFrame(controller.currentPositionSeconds), 1500);

    await controller.jumpToMarkIn();
    expect(secondsToTimecodeFrame(controller.currentPositionSeconds), 1050);

    await controller.jumpToTimelineStart();
    expect(controller.currentPositionSeconds, 0);

    await controller.jumpToTimelineEnd();
    expect(secondsToTimecodeFrame(controller.currentPositionSeconds), 3600);
  });

  test('jkl shuttle controls update playback direction and rate', () async {
    final controller = EditorController(autoStartEngine: false)..duration = 120;

    expect(controller.playbackShuttleLabel, 'K Stop');

    await controller.shuttleForward();
    expect(controller.playbackShuttleDirection, 1);
    expect(controller.playbackShuttleRate, 1.0);
    expect(controller.playbackShuttleLabel, 'L 1x');

    await controller.shuttleForward();
    expect(controller.playbackShuttleRate, 2.0);
    expect(controller.playbackShuttleLabel, 'L 2x');

    await controller.seekTo(20, autoplay: false);
    await controller.shuttleReverse();
    expect(controller.playbackShuttleDirection, -1);
    expect(controller.playbackShuttleRate, 1.0);
    expect(controller.playbackShuttleLabel, 'J 1x');

    await controller.shuttleReverse();
    expect(controller.playbackShuttleRate, 2.0);
    expect(controller.playbackShuttleLabel, 'J 2x');

    await controller.shuttlePause();
    expect(controller.playbackShuttleDirection, 0);
    expect(controller.playbackShuttleRate, 1.0);
    expect(controller.playbackShuttleLabel, 'K Stop');
    controller.dispose();
  });

  test('play request is retained while preview is preparing', () async {
    final controller = EditorController(autoStartEngine: false)
      ..selectedFile = PlatformFile(
        name: 'broadcast.mxf',
        size: 1024,
        path: r'C:\media\broadcast.mxf',
      )
      ..isPreparingPreview = true;

    await controller.togglePlayback();
    expect(controller.previewPlaybackQueued, isTrue);
    expect(controller.playbackShuttleDirection, 1);

    await controller.togglePlayback();
    expect(controller.previewPlaybackQueued, isFalse);
    expect(controller.playbackShuttleDirection, 0);
    controller.dispose();
  });

  test(
    'media probe restores full source duration after preview race',
    () async {
      final controller =
          EditorController(
              apiClient: _ProbeApiClient(),
              engineService: _ReadyEngineService(),
              autoStartEngine: false,
            )
            ..selectedFile = PlatformFile(
              name: 'cached-preview-source.mp4',
              size: 1024,
              path: r'C:\media\cached-preview-source.mp4',
            )
            ..duration = 0;

      await controller.probeSelectedMedia();

      expect(controller.duration, 3035.767);
      expect(controller.selectedMediaProbe?.canAnalyze, isTrue);
      controller.dispose();
    },
  );

  test('disabled timeline markers are skipped by marker rough cut', () async {
    final controller = EditorController(autoStartEngine: false)
      ..duration = 120
      ..timelineMarkers = const [
        TimelineMarker(
          id: 1,
          seconds: 10,
          label: 'Skip',
          color: 'rose',
          enabled: false,
        ),
        TimelineMarker(id: 2, seconds: 20, label: 'Hook', color: 'cyan'),
        TimelineMarker(id: 3, seconds: 40, label: 'Proof', color: 'green'),
      ];

    expect(controller.canBuildTimelineFromMarkers, isTrue);

    controller.replaceTimelineWithMarkerSegments();
    await Future<void>.delayed(Duration.zero);

    expect(controller.segments.length, 2);
    expect(controller.segments.first.reason, '마커 Hook 구간');
    expect(controller.segments.last.reason, '마커 Proof 구간');
    expect(controller.segments.first.start, 20);
    expect(controller.segments.first.end, 40);
    expect(controller.segments.last.start, 40);
    expect(controller.segments.last.end, 70);
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

  test('auto fix repairs detached audio length drift', () {
    final controller = EditorController(autoStartEngine: false)
      ..duration = 120
      ..segments = const [
        HighlightSegment(
          order: 1,
          start: 10,
          end: 20,
          reason: 'test',
          audioStart: 30,
          audioEnd: 45,
          audioLinked: false,
        ),
      ]
      ..selectedSegmentOrder = 1;

    expect(
      controller.audioVideoLengthDriftFrames(controller.segments.first),
      150,
    );
    expect(
      controller.segmentHasAudioLengthDrift(controller.segments.first),
      isTrue,
    );
    expect(
      controller.autoFixQueue.any(
        (item) => item.action == AutoFixAction.syncAudioLength,
      ),
      isTrue,
    );

    controller.applyAutoFixForSegment(1, AutoFixAction.syncAudioLength);

    final selected = controller.selectedSegment!;
    expect(selected.audioLinked, isFalse);
    expect(secondsToTimecodeFrame(selected.effectiveAudioStart), 900);
    expect(secondsToTimecodeFrame(selected.effectiveAudioEnd), 1200);
    expect(controller.segmentHasAudioLengthDrift(selected), isFalse);
  });

  test('slip edit moves source frames while preserving clip duration', () {
    final controller = EditorController(autoStartEngine: false)
      ..duration = 120
      ..segments = const [
        HighlightSegment(order: 1, start: 10, end: 20, reason: 'test'),
      ]
      ..selectedSegmentOrder = 1;

    controller.slipSelectedSegmentFrames(1);
    var selected = controller.selectedSegment!;
    expect(secondsToTimecodeFrame(selected.start), 301);
    expect(secondsToTimecodeFrame(selected.end), 601);
    expect(secondsToTimecodeFrame(selected.effectiveAudioStart), 301);
    expect(secondsToTimecodeFrame(selected.effectiveAudioEnd), 601);
    expect(secondsToTimecodeFrame(selected.end - selected.start), 300);
    expect(selected.source, contains('slip'));

    controller.slipSelectedSegmentFrames(-1000);
    selected = controller.selectedSegment!;
    expect(secondsToTimecodeFrame(selected.start), 0);
    expect(secondsToTimecodeFrame(selected.end), 300);
  });

  test('slip edit preserves detached audio offset by frame count', () {
    final controller = EditorController(autoStartEngine: false)
      ..duration = 120
      ..segments = const [
        HighlightSegment(
          order: 1,
          start: 10,
          end: 20,
          reason: 'test',
          audioStart: 40,
          audioEnd: 50,
          audioLinked: false,
        ),
      ]
      ..selectedSegmentOrder = 1;

    controller.slipSelectedSegmentFrames(10);

    final selected = controller.selectedSegment!;
    expect(secondsToTimecodeFrame(selected.start), 310);
    expect(secondsToTimecodeFrame(selected.end), 610);
    expect(selected.audioLinked, isFalse);
    expect(secondsToTimecodeFrame(selected.effectiveAudioStart), 1210);
    expect(secondsToTimecodeFrame(selected.effectiveAudioEnd), 1510);
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

  test('copy cut and paste selected clips use an editor clipboard', () {
    final controller = EditorController(autoStartEngine: false)
      ..duration = 60
      ..segments = const [
        HighlightSegment(order: 1, start: 0, end: 5, reason: 'a'),
        HighlightSegment(order: 2, start: 10, end: 15, reason: 'b'),
      ]
      ..selectedSegmentOrder = 1;

    expect(controller.hasClipClipboard, isFalse);

    controller.copySelectedSegment();
    expect(controller.hasClipClipboard, isTrue);
    expect(controller.clipClipboardLabel, contains('C1'));

    controller.selectedSegmentOrder = 2;
    controller.pasteClipboardSegment();
    expect(controller.segments.length, 3);
    expect(controller.selectedSegmentOrder, 3);
    expect(secondsToTimecodeFrame(controller.segments[2].start), 0);
    expect(secondsToTimecodeFrame(controller.segments[2].end), 150);
    expect(controller.segments[2].reason, contains('paste'));
    expect(controller.segments[2].source, contains('paste'));

    controller.selectedSegmentOrder = 2;
    controller.cutSelectedSegment();
    expect(controller.segments.length, 2);
    expect(controller.hasClipClipboard, isTrue);

    controller.pasteClipboardSegment();
    expect(controller.segments.length, 3);
    expect(secondsToTimecodeFrame(controller.segments.last.start), 300);
    expect(secondsToTimecodeFrame(controller.segments.last.end), 450);
    expect(controller.segments.last.reason, contains('paste'));
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

  test('extract marked range removes source spans and closes the edit', () {
    final controller = EditorController(autoStartEngine: false)
      ..duration = 90
      ..segments = const [
        HighlightSegment(order: 1, start: 0, end: 20, reason: 'a'),
        HighlightSegment(order: 2, start: 20, end: 50, reason: 'b'),
        HighlightSegment(order: 3, start: 50, end: 80, reason: 'c'),
      ]
      ..selectedSegmentOrder = 2;

    controller.setMarkInAt(30);
    controller.setMarkOutAt(60);
    expect(controller.canLiftOrExtractMarkedRange, isTrue);

    controller.extractMarkedRange();

    expect(controller.segments.length, 3);
    expect(secondsToTimecodeFrame(controller.segments[0].start), 0);
    expect(secondsToTimecodeFrame(controller.segments[0].end), 600);
    expect(secondsToTimecodeFrame(controller.segments[1].start), 600);
    expect(secondsToTimecodeFrame(controller.segments[1].end), 900);
    expect(secondsToTimecodeFrame(controller.segments[2].start), 1800);
    expect(secondsToTimecodeFrame(controller.segments[2].end), 2400);
    expect(controller.segments.any((item) => !item.videoEnabled), isFalse);
    expect(controller.outputDurationSeconds, closeTo(50, 0.001));

    controller.undo();
    expect(controller.segments.length, 3);
    expect(secondsToTimecodeFrame(controller.segments[1].end), 1500);
  });

  test('lift marked range leaves a black silent gap', () {
    final controller = EditorController(autoStartEngine: false)
      ..duration = 90
      ..segments = const [
        HighlightSegment(order: 1, start: 10, end: 70, reason: 'wide'),
      ]
      ..selectedSegmentOrder = 1;

    controller.setMarkInAt(30);
    controller.setMarkOutAt(50);
    controller.liftMarkedRange();

    expect(controller.segments.length, 3);
    expect(secondsToTimecodeFrame(controller.segments[0].start), 300);
    expect(secondsToTimecodeFrame(controller.segments[0].end), 900);
    expect(secondsToTimecodeFrame(controller.segments[1].start), 900);
    expect(secondsToTimecodeFrame(controller.segments[1].end), 1500);
    expect(controller.segments[1].videoEnabled, isFalse);
    expect(controller.segments[1].audioMuted, isTrue);
    expect(controller.segments[1].source, contains('lift-gap'));
    expect(secondsToTimecodeFrame(controller.segments[2].start), 1500);
    expect(secondsToTimecodeFrame(controller.segments[2].end), 2100);
    expect(controller.outputDurationSeconds, closeTo(60, 0.001));
  });

  test('timeline gaps can be detected and ripple deleted', () {
    final controller = EditorController(autoStartEngine: false)
      ..duration = 90
      ..segments = const [
        HighlightSegment(order: 1, start: 10, end: 70, reason: 'wide'),
      ]
      ..selectedSegmentOrder = 1;

    controller.setMarkInAt(30);
    controller.setMarkOutAt(50);
    controller.liftMarkedRange();

    expect(controller.hasTimelineGaps, isTrue);
    expect(controller.timelineGapCount, 1);
    expect(controller.segmentIsTimelineGap(controller.segments[1]), isTrue);
    expect(
      controller.autoFixQueue.any(
        (item) => item.action == AutoFixAction.closeGap,
      ),
      isTrue,
    );
    expect(controller.renderSafetyBlockCount, 0);
    expect(
      controller.renderSafetyChecklist.any(
        (item) =>
            item.label == 'Clip 2 gap' &&
            item.status == EditorialCheckStatus.warn,
      ),
      isTrue,
    );

    controller.selectSegment(2);
    controller.closeSelectedTimelineGap();

    expect(controller.hasTimelineGaps, isFalse);
    expect(controller.segments.length, 2);
    expect(controller.selectedSegmentOrder, 2);
    expect(controller.outputDurationSeconds, closeTo(40, 0.001));

    controller.undo();
    expect(controller.hasTimelineGaps, isTrue);

    controller.closeTimelineGaps();
    expect(controller.hasTimelineGaps, isFalse);
    expect(controller.segments.length, 2);
    expect(controller.outputDurationSeconds, closeTo(40, 0.001));
  });

  test('selected clip lift and extract mirror premiere edit behavior', () {
    final controller = EditorController(autoStartEngine: false)
      ..duration = 90
      ..segments = const [
        HighlightSegment(order: 1, start: 0, end: 10, reason: 'one'),
        HighlightSegment(order: 2, start: 20, end: 40, reason: 'two'),
        HighlightSegment(order: 3, start: 50, end: 60, reason: 'three'),
      ]
      ..selectedSegmentOrder = 2;

    final originalOutputFrames = secondsToTimecodeFrame(
      controller.outputDurationSeconds,
    );

    controller.liftSelectedSegment();

    expect(controller.segments.length, 3);
    expect(controller.selectedSegmentOrder, 2);
    expect(controller.segments[1].videoEnabled, isFalse);
    expect(controller.segments[1].audioMuted, isTrue);
    expect(controller.segments[1].source, contains('lift-gap'));
    expect(
      secondsToTimecodeFrame(controller.outputDurationSeconds),
      originalOutputFrames,
    );

    controller.undo();
    controller.extractSelectedSegment();

    expect(controller.segments.length, 2);
    expect(controller.selectedSegmentOrder, 2);
    expect(controller.segments[1].reason, 'three');
    expect(
      secondsToTimecodeFrame(controller.outputDurationSeconds),
      originalOutputFrames - 600,
    );
  });

  test('track targets lift only selected tracks inside marked range', () {
    final controller = EditorController(autoStartEngine: false)
      ..duration = 90
      ..segments = const [
        HighlightSegment(order: 1, start: 10, end: 70, reason: 'wide'),
      ]
      ..selectedSegmentOrder = 1;

    controller.toggleVideoTrackTarget();
    controller.toggleAudioTrack2Target();
    expect(controller.videoTrackTargeted, isFalse);
    expect(controller.audioTrack1Targeted, isTrue);
    expect(controller.audioTrack2Targeted, isFalse);

    controller.setMarkInAt(30);
    controller.setMarkOutAt(50);
    controller.liftMarkedRange();

    expect(controller.segments.length, 3);
    final targetedGap = controller.segments[1];
    expect(targetedGap.videoEnabled, isTrue);
    expect(targetedGap.audioChannel1Enabled, isFalse);
    expect(targetedGap.audioChannel2Enabled, isTrue);
    expect(targetedGap.audioMuted, isFalse);
    expect(targetedGap.source, contains('target-lift'));
    expect(controller.outputDurationSeconds, closeTo(60, 0.001));
  });

  test('partial track target extract preserves timeline duration', () {
    final controller = EditorController(autoStartEngine: false)
      ..duration = 90
      ..segments = const [
        HighlightSegment(order: 1, start: 10, end: 70, reason: 'wide'),
      ]
      ..selectedSegmentOrder = 1;

    controller.toggleAudioTrack1Target();
    controller.toggleAudioTrack2Target();
    expect(controller.videoTrackTargeted, isTrue);
    expect(controller.audioTrack1Targeted, isFalse);
    expect(controller.audioTrack2Targeted, isFalse);

    controller.setMarkInAt(30);
    controller.setMarkOutAt(50);
    controller.extractMarkedRange();

    expect(controller.segments.length, 3);
    final targetedGap = controller.segments[1];
    expect(targetedGap.videoEnabled, isFalse);
    expect(targetedGap.audioChannel1Enabled, isTrue);
    expect(targetedGap.audioChannel2Enabled, isTrue);
    expect(targetedGap.audioMuted, isFalse);
    expect(targetedGap.source, contains('target-lift'));
    expect(controller.outputDurationSeconds, closeTo(60, 0.001));
  });

  test('extract marked range preserves detached audio timing', () {
    final controller = EditorController(autoStartEngine: false)
      ..duration = 200
      ..segments = const [
        HighlightSegment(
          order: 1,
          start: 10,
          end: 70,
          reason: 'detached',
          audioStart: 110,
          audioEnd: 170,
          audioLinked: false,
        ),
      ]
      ..selectedSegmentOrder = 1;

    controller.setMarkInAt(30);
    controller.setMarkOutAt(50);
    controller.extractMarkedRange();

    expect(controller.segments.length, 2);
    expect(controller.segments[0].audioLinked, isFalse);
    expect(controller.segments[1].audioLinked, isFalse);
    expect(
      secondsToTimecodeFrame(controller.segments[0].effectiveAudioStart),
      3300,
    );
    expect(
      secondsToTimecodeFrame(controller.segments[0].effectiveAudioEnd),
      3900,
    );
    expect(
      secondsToTimecodeFrame(controller.segments[1].effectiveAudioStart),
      4500,
    );
    expect(
      secondsToTimecodeFrame(controller.segments[1].effectiveAudioEnd),
      5100,
    );
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

    controller.addEditAt(8);
    expect(controller.segments.length, 2);
    expect(secondsToTimecodeFrame(controller.segments.first.end), 240);
    expect(secondsToTimecodeFrame(controller.segments.last.start), 240);

    controller.selectSegment(2);
    controller.applyDefaultVideoTransition();
    controller.applyDefaultAudioTransition();
    expect(controller.selectedSegment!.transitionType, 'cross_dissolve');
    expect(controller.selectedSegment!.transitionDuration, 0.3);
    expect(controller.outputDurationSeconds, closeTo(7.7, 0.001));
  });

  test('insert and overwrite edits use marked source range', () {
    final controller = EditorController(autoStartEngine: false)
      ..duration = 90
      ..segments = const [
        HighlightSegment(order: 1, start: 0, end: 10, reason: 'one'),
        HighlightSegment(order: 2, start: 20, end: 30, reason: 'two'),
      ]
      ..selectedSegmentOrder = 2;

    controller.setMarkInAt(40);
    controller.setMarkOutAt(46);
    controller.insertMarkedSegmentAtSelection();

    expect(controller.segments.length, 3);
    expect(controller.selectedSegmentOrder, 2);
    expect(controller.segments[1].reason, 'Insert In/Out edit');
    expect(secondsToTimecodeFrame(controller.segments[1].start), 1200);
    expect(secondsToTimecodeFrame(controller.segments[1].end), 1380);
    expect(controller.segments[2].reason, 'two');

    controller.setMarkInAt(50);
    controller.setMarkOutAt(58);
    controller.overwriteSelectedSegmentWithMarks();

    expect(controller.segments.length, 3);
    expect(controller.segments[1].reason, 'Overwrite In/Out edit');
    expect(secondsToTimecodeFrame(controller.segments[1].start), 1500);
    expect(secondsToTimecodeFrame(controller.segments[1].end), 1740);
    expect(controller.segments[1].source, contains('overwrite'));
  });

  test('audio only overwrite preserves selected video range', () {
    final controller = EditorController(autoStartEngine: false)
      ..duration = 90
      ..segments = const [
        HighlightSegment(order: 1, start: 10, end: 30, reason: 'sync'),
      ]
      ..selectedSegmentOrder = 1;

    controller.toggleVideoTrackTarget();
    expect(controller.videoTrackTargeted, isFalse);
    expect(controller.audioTrack1Targeted, isTrue);
    expect(controller.audioTrack2Targeted, isTrue);

    controller.setMarkInAt(50);
    controller.setMarkOutAt(60);
    controller.overwriteSelectedSegmentWithMarks();

    final selected = controller.selectedSegment!;
    expect(secondsToTimecodeFrame(selected.start), 300);
    expect(secondsToTimecodeFrame(selected.end), 900);
    expect(secondsToTimecodeFrame(selected.effectiveAudioStart), 1500);
    expect(secondsToTimecodeFrame(selected.effectiveAudioEnd), 1800);
    expect(selected.audioLinked, isFalse);
    expect(selected.videoEnabled, isTrue);
    expect(selected.audioMuted, isFalse);
  });

  test('rolling trim preserves total timeline duration across edit points', () {
    final controller = EditorController(autoStartEngine: false)
      ..duration = 60
      ..segments = const [
        HighlightSegment(order: 1, start: 0, end: 10, reason: 'first'),
        HighlightSegment(order: 2, start: 20, end: 30, reason: 'second'),
        HighlightSegment(order: 3, start: 40, end: 50, reason: 'third'),
      ]
      ..selectedSegmentOrder = 2;

    final originalOutputFrames = secondsToTimecodeFrame(
      controller.outputDurationSeconds,
    );

    controller.rollSelectedIncomingEditFrames(5);

    expect(secondsToTimecodeFrame(controller.segments[0].end), 305);
    expect(secondsToTimecodeFrame(controller.segments[1].start), 605);
    expect(
      secondsToTimecodeFrame(controller.outputDurationSeconds),
      originalOutputFrames,
    );
    expect(controller.segments[0].source, contains('roll'));
    expect(controller.segments[1].source, contains('roll'));

    controller.rollSelectedOutgoingEditFrames(-10);

    expect(secondsToTimecodeFrame(controller.segments[1].end), 890);
    expect(secondsToTimecodeFrame(controller.segments[2].start), 1190);
    expect(
      secondsToTimecodeFrame(controller.outputDurationSeconds),
      originalOutputFrames,
    );

    controller.toggleVideoTrackLock();
    controller.rollSelectedIncomingEditFrames(10);
    expect(secondsToTimecodeFrame(controller.segments[0].end), 305);
    expect(secondsToTimecodeFrame(controller.segments[1].start), 605);
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
    expect(controller.allAudioChannel1Enabled, isTrue);
    expect(controller.allAudioChannel2Enabled, isTrue);
    controller.toggleAllAudioChannel2();
    expect(
      controller.segments.every((segment) => !segment.audioChannel2Enabled),
      isTrue,
    );
    expect(controller.allAudioChannel2Enabled, isFalse);
    controller.toggleAllAudioChannel1();
    expect(
      controller.segments.every((segment) => !segment.audioChannel1Enabled),
      isTrue,
    );
    expect(
      controller.segments.every((segment) => segment.audioChannel2Enabled),
      isTrue,
    );
    controller.soloAudioChannel1Track();
    expect(
      controller.segments.every((segment) => segment.audioChannel1Enabled),
      isTrue,
    );
    expect(
      controller.segments.every((segment) => !segment.audioChannel2Enabled),
      isTrue,
    );
    expect(controller.segments.every((segment) => !segment.audioMuted), isTrue);
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
    controller.soloAudioChannel2Track();
    expect(
      controller.segments.every((segment) => !segment.audioChannel2Enabled),
      isTrue,
    );
    controller.toggleAllAudioMute();
    expect(controller.segments.every((segment) => segment.audioMuted), isTrue);
  });

  test('individual audio track locks protect A1 and A2 edits', () {
    final controller = EditorController(autoStartEngine: false)
      ..duration = 30
      ..segments = const [
        HighlightSegment(order: 1, start: 5, end: 13, reason: 'test'),
        HighlightSegment(order: 2, start: 15, end: 20, reason: 'test 2'),
      ]
      ..selectedSegmentOrder = 1;

    controller.toggleAudioTrack1Lock();
    expect(controller.audioTrack1Locked, isTrue);
    expect(controller.audioTrack1EditLocked, isTrue);
    expect(controller.audioTrack2EditLocked, isFalse);
    expect(controller.audioTrackLockLabel, 'A1 Locked');

    controller.toggleSelectedAudioChannel1();
    expect(controller.selectedSegment!.audioChannel1Enabled, isTrue);

    controller.toggleSelectedAudioChannel2();
    expect(controller.selectedSegment!.audioChannel2Enabled, isFalse);

    controller.setSelectedAudioPan(1);
    expect(controller.selectedSegment!.audioPan, 0);

    controller.toggleAudioTrack1Lock();
    controller.toggleAudioTrack2Lock();
    expect(controller.audioTrack1EditLocked, isFalse);
    expect(controller.audioTrack2EditLocked, isTrue);
    expect(controller.audioTrackLockLabel, 'A2 Locked');

    controller.toggleSelectedAudioChannel2();
    expect(controller.selectedSegment!.audioChannel2Enabled, isFalse);

    controller.toggleSelectedAudioChannel1();
    expect(controller.selectedSegment!.audioChannel1Enabled, isTrue);

    controller.toggleAllAudioMute();
    expect(controller.segments.every((segment) => !segment.audioMuted), isTrue);
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

  test(
    'render safety gate blocks unsafe exports until timeline is repaired',
    () {
      final controller = EditorController(autoStartEngine: false)
        ..jobId = 'job-1'
        ..duration = 120
        ..includeCaptions = true
        ..segments = const [
          HighlightSegment(
            order: 1,
            start: 10,
            end: 10.4,
            reason: '미확인 루머',
            script: '확인되지 않은 내용입니다',
            videoEnabled: false,
            audioStart: 12,
            audioEnd: 11,
            audioMuted: true,
          ),
        ]
        ..captions = const [];

      expect(controller.canPassRenderSafety, isFalse);
      expect(controller.canRender, isFalse);
      expect(controller.renderSafetyBlockCount, greaterThanOrEqualTo(4));
      expect(
        controller.renderSafetyChecklist.any(
          (item) => item.label == 'Clip 1 video',
        ),
        isTrue,
      );
      expect(
        controller.renderSafetyChecklist.any(
          (item) => item.label == 'Clip 1 risk',
        ),
        isTrue,
      );

      controller.segments = const [
        HighlightSegment(
          order: 1,
          start: 10,
          end: 22,
          reason: '검증된 핵심 설명',
          script: '출처가 확인된 핵심 설명입니다',
          audioNormalize: true,
          tags: ['뉴스핵심', '근거'],
        ),
      ];
      controller.captions = const [
        CaptionSegment(order: 1, start: 10, end: 22, text: '출처가 확인된 핵심 설명입니다'),
      ];

      expect(controller.renderSafetyBlockCount, 0);
      expect(controller.canPassRenderSafety, isTrue);
      expect(controller.canRender, isTrue);
    },
  );

  test('render safety blocks news timelines without verification evidence', () {
    final controller = EditorController(autoStartEngine: false)
      ..jobId = 'job-news-unverified'
      ..duration = 220
      ..segments = const [
        HighlightSegment(
          order: 1,
          start: 0,
          end: 82,
          reason: '속보 정부 대책',
          script: '정부가 새 대책을 발표했습니다',
          tags: ['뉴스핵심'],
          audioNormalize: true,
        ),
        HighlightSegment(
          order: 2,
          start: 86,
          end: 172,
          reason: '피해 영향',
          script: '현장 피해 규모와 후속 대응을 정리합니다',
          tags: ['영향', '대응'],
          audioNormalize: true,
        ),
      ];

    expect(
      controller.renderSafetyChecklist.any(
        (item) =>
            item.label == 'News verification' &&
            item.status == EditorialCheckStatus.block,
      ),
      isTrue,
    );
    expect(controller.hasManualRenderSafetyBlock, isTrue);
    expect(controller.canPassRenderSafety, isFalse);
    expect(
      controller.autoFixQueue.any(
        (item) =>
            item.title == 'Needs verification' &&
            item.severity == AutoFixSeverity.block &&
            item.action == AutoFixAction.selectForReview,
      ),
      isTrue,
    );
  });

  test('verified fact tags clear the news render verification gate', () {
    final controller = EditorController(autoStartEngine: false)
      ..jobId = 'job-news-verified'
      ..duration = 220
      ..segments = const [
        HighlightSegment(
          order: 1,
          start: 0,
          end: 82,
          reason: '공식 발표 핵심',
          script: '공식 브리핑에서 확인된 수치를 설명합니다',
          tags: ['뉴스핵심', '검증팩트'],
          audioNormalize: true,
        ),
        HighlightSegment(
          order: 2,
          start: 86,
          end: 172,
          reason: '영향과 대응',
          script: '현장 영향과 후속 대응을 정리합니다',
          tags: ['영향', '대응'],
          audioNormalize: true,
        ),
      ];

    expect(
      controller.renderSafetyChecklist.any(
        (item) => item.label == 'News verification',
      ),
      isFalse,
    );
    expect(controller.renderSafetyBlockCount, 0);
    expect(controller.canPassRenderSafety, isTrue);
  });

  test('render safety auto repair fixes mechanical export blockers', () {
    final controller = EditorController(autoStartEngine: false)
      ..jobId = 'job-2'
      ..duration = 120
      ..segments = const [
        HighlightSegment(
          order: 1,
          start: 10,
          end: 10.4,
          reason: '검증된 짧은 설명',
          script: '출처가 확인된 짧은 설명입니다',
          videoEnabled: false,
          audioStart: 12,
          audioEnd: 11,
          audioMuted: true,
          videoFadeIn: 2,
          videoFadeOut: 2,
          audioFadeIn: 2,
          audioFadeOut: 2,
        ),
      ];

    expect(controller.renderSafetyBlockCount, greaterThan(0));
    expect(controller.canRender, isTrue);

    controller.applyRenderSafetyAutoRepair();

    expect(controller.renderSafetyBlockCount, 0);
    expect(controller.canRender, isTrue);
    expect(controller.segments.first.videoEnabled, isTrue);
    expect(controller.segments.first.audioMuted, isFalse);
    expect(controller.segments.first.hasActiveAudioChannel, isTrue);
    expect(controller.segments.first.audioNormalize, isTrue);
    expect(controller.segments.first.duration, greaterThanOrEqualTo(2.0));
    expect(
      controller.segments.first.videoFadeIn +
          controller.segments.first.videoFadeOut,
      lessThan(controller.segments.first.duration),
    );
  });

  test(
    'render request auto repairs mechanical blockers before API call',
    () async {
      final apiClient = _RecordingApiClient();
      final controller =
          EditorController(apiClient: apiClient, autoStartEngine: false)
            ..jobId = 'job-3'
            ..duration = 120
            ..segments = const [
              HighlightSegment(
                order: 1,
                start: 10,
                end: 10.4,
                reason: '검증된 짧은 설명',
                script: '출처가 확인된 짧은 설명입니다',
                videoEnabled: false,
                audioStart: 12,
                audioEnd: 11,
                audioMuted: true,
              ),
            ];

      expect(controller.renderSafetyBlockCount, greaterThan(0));
      expect(controller.canRender, isTrue);

      await controller.requestRender();

      expect(apiClient.renderRequested, isTrue);
      expect(controller.renderSafetyBlockCount, 0);
      expect(apiClient.renderSegments.single.videoEnabled, isTrue);
      expect(apiClient.renderSegments.single.audioMuted, isFalse);
      expect(apiClient.renderSegments.single.audioNormalize, isTrue);
      expect(
        apiClient.renderSegments.single.duration,
        greaterThanOrEqualTo(2.0),
      );
      await Future<void>.delayed(Duration.zero);
      controller.dispose();
    },
  );

  test(
    'multi format export sends one batch item per selected profile',
    () async {
      final apiClient = _RecordingApiClient();
      final controller =
          EditorController(apiClient: apiClient, autoStartEngine: false)
            ..jobId = 'job-multi'
            ..duration = 120
            ..includeCaptions = true
            ..captions = const [
              CaptionSegment(order: 1, start: 10, end: 40, text: 'caption'),
            ]
            ..segments = const [
              HighlightSegment(
                order: 1,
                start: 10,
                end: 40,
                reason: '검증된 설명',
                script: '공식 출처가 확인된 설명입니다',
                audioNormalize: true,
              ),
            ];

      controller.setExportProfiles({'16:9', '9:16', '1:1'});
      expect(controller.hasMultiFormatExport, isTrue);
      expect(controller.exportProfilesLabel, contains('YouTube 16:9'));
      expect(controller.exportProfilesLabel, contains('Shorts 9:16'));
      expect(controller.exportProfilesLabel, contains('Square 1:1'));

      await controller.requestRender();

      expect(apiClient.renderRequested, isFalse);
      expect(apiClient.batchRenderRequested, isTrue);
      expect(apiClient.batchRenderItems, hasLength(3));
      expect(
        apiClient.batchRenderItems.map((item) => item['aspect_ratio']).toList(),
        ['16:9', '9:16', '1:1'],
      );
      expect(
        apiClient.batchRenderItems.map((item) => item['output_name']).toList(),
        [
          'youtube_highlights_16x9.mp4',
          'youtube_shorts_9x16.mp4',
          'social_square_1x1.mp4',
        ],
      );
      await Future<void>.delayed(Duration.zero);
      controller.dispose();
    },
  );

  test('offline fallback review clips are surfaced as preflight warnings', () {
    final controller = EditorController(autoStartEngine: false)
      ..jobId = 'job-offline'
      ..duration = 120
      ..segments = const [
        HighlightSegment(
          order: 1,
          start: 20,
          end: 55,
          reason: 'STT 없이 오디오 활동 기반으로 잡은 검토용 후보',
          source: 'fallback-audio-review',
          audioNormalize: true,
          tags: ['검토필요', '오디오활성', 'STT미설정'],
        ),
      ];

    expect(controller.offlineReviewSegmentCount, 1);
    expect(controller.hasOfflineReviewSegments, isTrue);
    expect(controller.canRender, isTrue);
    expect(
      controller.editorialChecklist.any(
        (item) =>
            item.label == 'Offline review' &&
            item.status == EditorialCheckStatus.warn,
      ),
      isTrue,
    );
    expect(
      controller.renderSafetyChecklist.any(
        (item) =>
            item.label == 'Clip 1 review' &&
            item.status == EditorialCheckStatus.warn,
      ),
      isTrue,
    );
  });

  test('shorts quality flags offline review candidates', () {
    final controller = EditorController(autoStartEngine: false)
      ..duration = 240
      ..segments = const [
        HighlightSegment(
          order: 1,
          start: 20,
          end: 65,
          reason: 'STT 없이 오디오 활동 기반으로 잡은 검토용 후보',
          source: 'fallback-audio-review',
          score: 8,
          audioNormalize: true,
          tags: ['검토필요', '오디오활성', 'STT미설정'],
        ),
        HighlightSegment(
          order: 2,
          start: 80,
          end: 130,
          reason: '검증된 핵심 설명',
          script: '출처가 확인된 핵심 설명입니다',
          score: 8,
          audioNormalize: true,
          tags: ['뉴스핵심', '근거'],
        ),
      ];

    controller.buildMultiShortsCandidates(maxCandidates: 2);

    expect(controller.hasShortsCandidates, isTrue);
    expect(
      controller.shortsCandidates.any(
        (candidate) => candidate.issues.contains('Offline review'),
      ),
      isTrue,
    );
    final offlineCandidate = controller.shortsCandidates.firstWhere(
      (candidate) => candidate.issues.contains('Offline review'),
    );
    expect(offlineCandidate.qualityScore, lessThan(85));
    expect(offlineCandidate.qualityGrade, isNot('S'));
    expect(offlineCandidate.isPublishReady, isFalse);
    expect(offlineCandidate.readinessLabel, isNot('Ready'));
  });

  test('shorts readiness auto-selects only publish ready candidates', () {
    final controller = EditorController(autoStartEngine: false)
      ..duration = 240
      ..captions = const [
        CaptionSegment(order: 1, start: 10, end: 65, text: '검증된 핵심 후킹 설명'),
        CaptionSegment(order: 2, start: 100, end: 155, text: '검토용 오디오 후보'),
      ]
      ..segments = const [
        HighlightSegment(
          order: 1,
          start: 10,
          end: 65,
          reason: '핵심 결과와 후킹이 분명한 검증된 설명',
          script: '출처가 확인된 핵심 결과를 먼저 설명합니다',
          score: 9,
          audioNormalize: true,
          tags: ['유지율', '뉴스핵심', '근거'],
        ),
        HighlightSegment(
          order: 2,
          start: 100,
          end: 155,
          reason: 'STT 없이 오디오 활동 기반으로 잡은 검토용 후보',
          source: 'fallback-audio-review',
          score: 9,
          audioNormalize: true,
          tags: ['검토필요', '오디오활성', 'STT미설정'],
        ),
      ];

    controller.buildMultiShortsCandidates(
      maxCandidates: 3,
      minSeconds: 40,
      maxSeconds: 70,
    );

    expect(controller.hasShortsCandidates, isTrue);
    expect(
      controller.shortsCandidates.any((candidate) => candidate.isPublishReady),
      isTrue,
    );
    expect(
      controller.shortsCandidates
          .where((candidate) => candidate.selected)
          .every((candidate) => candidate.isPublishReady),
      isTrue,
    );
    expect(
      controller.selectedShortsCount,
      controller.shortsCandidates
          .where((candidate) => candidate.isPublishReady)
          .length,
    );
    final offlineCandidate = controller.shortsCandidates.firstWhere(
      (candidate) => candidate.issues.contains('Offline review'),
    );
    expect(offlineCandidate.selected, isFalse);
    expect(offlineCandidate.readinessLabel, 'Review');
  });

  test('selected shorts safety repair only updates selected candidates', () {
    final controller = EditorController(autoStartEngine: false)
      ..duration = 120
      ..selectedShortsId = 1
      ..shortsCandidates = const [
        ShortsCandidate(
          id: 1,
          label: 'Shorts 01',
          reason: 'selected',
          selected: true,
          segments: [
            HighlightSegment(
              order: 1,
              start: 10,
              end: 10.4,
              reason: '검증된 짧은 설명',
              script: '출처가 확인된 짧은 설명입니다',
              videoEnabled: false,
              audioStart: 12,
              audioEnd: 11,
              audioMuted: true,
            ),
          ],
        ),
        ShortsCandidate(
          id: 2,
          label: 'Shorts 02',
          reason: 'not selected',
          selected: false,
          segments: [
            HighlightSegment(
              order: 1,
              start: 20,
              end: 20.4,
              reason: '검증된 짧은 설명',
              videoEnabled: false,
              audioMuted: true,
            ),
          ],
        ),
      ];

    expect(controller.selectedShortsRenderBlockCount, greaterThan(0));

    controller.applySelectedShortsRenderSafetyAutoRepair();

    final repaired = controller.shortsCandidates.first;
    final untouched = controller.shortsCandidates.last;
    expect(controller.selectedShortsRenderBlockCount, 0);
    expect(repaired.segments.first.videoEnabled, isTrue);
    expect(repaired.segments.first.audioMuted, isFalse);
    expect(repaired.segments.first.audioNormalize, isTrue);
    expect(repaired.segments.first.duration, greaterThanOrEqualTo(2.0));
    expect(repaired.qualityScore, greaterThan(0));
    expect(untouched.segments.first.videoEnabled, isFalse);
    expect(untouched.segments.first.audioMuted, isTrue);
    expect(controller.segments.first.videoEnabled, isTrue);
  });

  test('selected shorts export queue mirrors batch render order', () {
    final controller = EditorController(autoStartEngine: false)
      ..duration = 240
      ..captions = const [
        CaptionSegment(order: 1, start: 10, end: 80, text: 'ready'),
        CaptionSegment(order: 2, start: 100, end: 120, text: 'blocked'),
      ]
      ..shortsCandidates = const [
        ShortsCandidate(
          id: 1,
          label: 'Ready 01',
          reason: 'selected ready candidate',
          selected: true,
          segments: [
            HighlightSegment(
              order: 1,
              start: 10,
              end: 80,
              reason: '검증된 설명',
              script: '출처가 확인된 설명입니다',
              audioNormalize: true,
            ),
          ],
        ),
        ShortsCandidate(
          id: 2,
          label: 'Ignored 02',
          reason: 'not selected',
          selected: false,
          segments: [
            HighlightSegment(
              order: 1,
              start: 82,
              end: 120,
              reason: '선택하지 않은 후보',
              audioNormalize: true,
            ),
          ],
        ),
        ShortsCandidate(
          id: 3,
          label: 'Blocked 03',
          reason: 'selected blocked candidate',
          selected: true,
          segments: [
            HighlightSegment(
              order: 1,
              start: 100,
              end: 100.4,
              reason: '검수 필요한 짧은 컷',
              videoEnabled: false,
              audioMuted: true,
            ),
          ],
        ),
      ];

    final queue = controller.selectedShortsExportQueue;

    expect(queue, hasLength(2));
    expect(queue.first.outputName, 'shorts_01.mp4');
    expect(queue.first.statusLabel, 'Ready');
    expect(queue.first.canRender, isTrue);
    expect(queue.first.clipCount, 1);
    expect(queue.last.outputName, 'shorts_02.mp4');
    expect(queue.last.statusLabel, 'Blocked');
    expect(queue.last.canRender, isFalse);
    expect(queue.last.statusDetail, contains('Clip 1'));
    expect(controller.selectedShortsExportReadyCount, 1);
    expect(controller.selectedShortsExportDurationSeconds, closeTo(70.4, 0.01));
  });

  test(
    'selected shorts render auto repairs candidates before batch API call',
    () async {
      final apiClient = _RecordingApiClient();
      final controller =
          EditorController(apiClient: apiClient, autoStartEngine: false)
            ..jobId = 'job-4'
            ..duration = 120
            ..selectedShortsId = 1
            ..shortsCandidates = const [
              ShortsCandidate(
                id: 1,
                label: 'Shorts 01',
                reason: 'selected',
                selected: true,
                segments: [
                  HighlightSegment(
                    order: 1,
                    start: 10,
                    end: 10.4,
                    reason: '검증된 짧은 설명',
                    script: '출처가 확인된 짧은 설명입니다',
                    videoEnabled: false,
                    audioStart: 12,
                    audioEnd: 11,
                    audioMuted: true,
                  ),
                ],
              ),
            ];

      expect(controller.selectedShortsRenderBlockCount, greaterThan(0));

      await controller.requestSelectedShortsRender();

      expect(apiClient.batchRenderRequested, isTrue);
      expect(controller.selectedShortsRenderBlockCount, 0);
      final rawSegments = apiClient.batchRenderItems.single['segments'] as List;
      final renderedSegment = rawSegments.single as Map<String, dynamic>;
      expect(renderedSegment['video_enabled'], isTrue);
      expect(renderedSegment['audio_muted'], isFalse);
      expect(renderedSegment['audio_normalize'], isTrue);
      await Future<void>.delayed(Duration.zero);
      controller.dispose();
    },
  );

  test('render outputs expose every batch render download link', () {
    final controller =
        EditorController(
            apiClient: _RecordingApiClient(),
            autoStartEngine: false,
          )
          ..renderUrl =
              'http://127.0.0.1:1/api/jobs/job-4/download/shorts_01.mp4'
          ..job = const JobStatusResponse(
            jobId: 'job-4',
            status: 'rendered',
            stage: 'batch_rendered',
            progress: 100,
            message: 'done',
            renderPath: 'C:/AutoEdit/outputs/shorts_01.mp4',
            renderDurationSeconds: 45.5,
            renderSizeBytes: 123456,
            renderWarnings: ['Shorts 02: 렌더 파일 크기가 매우 작습니다.'],
            renderUrl: '/api/jobs/job-4/download/shorts_01.mp4',
            batchRenderItems: [
              BatchRenderItemResult(
                label: 'Shorts 01',
                outputName: 'shorts_01.mp4',
                url: '/api/jobs/job-4/download/shorts_01.mp4',
                aspectRatio: '9:16',
                path: 'C:/AutoEdit/outputs/shorts_01.mp4',
                durationSeconds: 45.5,
                sizeBytes: 123456,
              ),
              BatchRenderItemResult(
                label: 'Shorts 02',
                outputName: 'shorts_02.mp4',
                url: '/api/jobs/job-4/download/shorts_02.mp4',
                aspectRatio: '1:1',
                path: 'C:/AutoEdit/outputs/shorts_02.mp4',
                durationSeconds: 61.2,
                sizeBytes: 234567,
                warnings: ['렌더 파일 크기가 매우 작습니다.'],
              ),
            ],
            renderManifestItems: [
              BatchRenderItemResult(
                label: 'Render Manifest JSON',
                outputName: 'render_manifest.json',
                url: '/api/jobs/job-4/download/render_manifest.json',
                kind: 'manifest',
                path: 'C:/AutoEdit/outputs/render_manifest.json',
                sizeBytes: 2048,
              ),
              BatchRenderItemResult(
                label: 'Render Manifest CSV',
                outputName: 'render_manifest.csv',
                url: '/api/jobs/job-4/download/render_manifest.csv',
                kind: 'manifest',
                path: 'C:/AutoEdit/outputs/render_manifest.csv',
                sizeBytes: 1024,
              ),
            ],
          );

    final outputs = controller.renderOutputs;

    expect(outputs, hasLength(4));
    expect(outputs.first.outputName, 'shorts_01.mp4');
    expect(outputs.first.aspectRatio, '9:16');
    expect(
      outputs.first.url,
      'http://127.0.0.1:1/api/jobs/job-4/download/shorts_01.mp4',
    );
    expect(
      outputs[1].url,
      'http://127.0.0.1:1/api/jobs/job-4/download/shorts_02.mp4',
    );
    expect(outputs[1].path, 'C:/AutoEdit/outputs/shorts_02.mp4');
    expect(outputs[1].aspectRatio, '1:1');
    expect(outputs[1].durationSeconds, 61.2);
    expect(outputs[1].sizeBytes, 234567);
    expect(outputs[1].warnings.single, contains('파일 크기'));
    expect(outputs[2].isManifest, isTrue);
    expect(outputs[2].outputName, 'render_manifest.json');
    expect(
      outputs[2].url,
      'http://127.0.0.1:1/api/jobs/job-4/download/render_manifest.json',
    );
    expect(outputs.last.outputName, 'render_manifest.csv');
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

    controller.buildMultiShortsCandidates(maxCandidates: 5);
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
    expect(controller.shortsCandidates.first.storyFlow, isNotEmpty);
    expect(controller.shortsCandidates.first.storyScore, greaterThan(0));
    expect(controller.shortsCandidates.first.hookScore, greaterThan(0));
    expect(controller.shortsCandidates.first.completionScore, greaterThan(0));
    expect(controller.shortsCandidates.first.storyFlow.first, 'Hook');
    expect(
      controller.shortsCandidates
          .map((candidate) => candidate.strategyKind)
          .toSet()
          .length,
      greaterThan(1),
    );

    final selectedId = controller.selectedShortsId!;
    final wasSelected = controller.shortsCandidates
        .firstWhere((candidate) => candidate.id == selectedId)
        .selected;
    controller.updateSegment(controller.segments.first.copyWith(end: 60));
    controller.updateSelectedShortsFromTimeline();
    final updatedCandidate = controller.shortsCandidates.firstWhere(
      (candidate) => candidate.id == selectedId,
    );
    expect(updatedCandidate.segments.first.end, closeTo(60, 0.01));
    expect(updatedCandidate.qualityScore, greaterThan(0));
    expect(updatedCandidate.hookScore, greaterThan(0));
    expect(updatedCandidate.completionScore, greaterThan(0));
    expect(updatedCandidate.storyFlow, isNotEmpty);

    controller.duplicateShortsCandidate(selectedId);
    expect(controller.shortsCandidates.length, greaterThan(1));
    expect(controller.shortsCandidates.last.qualityScore, greaterThan(0));

    controller.toggleShortsCandidate(selectedId);
    expect(
      controller.shortsCandidates
          .firstWhere((candidate) => candidate.id == selectedId)
          .selected,
      isNot(wasSelected),
    );

    controller.deleteShortsCandidate(selectedId);
    expect(
      controller.shortsCandidates.any(
        (candidate) => candidate.id == selectedId,
      ),
      isFalse,
    );
  });

  test('multi shorts candidates avoid near duplicate source coverage', () {
    final controller = EditorController(autoStartEngine: false)
      ..duration = 720
      ..segments = const [
        HighlightSegment(
          order: 1,
          start: 0,
          end: 60,
          reason: '결과부터 보는 뉴스 핵심',
          script: '공식 보고서로 확인된 첫 번째 핵심 장면입니다',
          score: 9,
          tags: ['뉴스핵심', '검증팩트', '근거', '유지율'],
          audioNormalize: true,
        ),
        HighlightSegment(
          order: 2,
          start: 8,
          end: 68,
          reason: '같은 뉴스 핵심 반복',
          script: '공식 보고서로 확인된 첫 번째 핵심 장면을 다시 설명합니다',
          score: 8.8,
          tags: ['뉴스핵심', '근거', '유지율'],
          audioNormalize: true,
        ),
        HighlightSegment(
          order: 3,
          start: 16,
          end: 76,
          reason: '같은 구간의 정보 설명',
          script: '첫 번째 핵심 장면의 수치와 원인을 덧붙입니다',
          score: 8.6,
          tags: ['문제해결', '구체성'],
          audioNormalize: true,
        ),
        HighlightSegment(
          order: 4,
          start: 180,
          end: 240,
          reason: '피해 영향',
          script: '주민 피해와 현장 영향을 정리합니다',
          score: 8,
          tags: ['영향'],
          audioNormalize: true,
        ),
        HighlightSegment(
          order: 5,
          start: 280,
          end: 340,
          reason: '대응',
          script: '정부와 회사의 후속 대응을 설명합니다',
          score: 7.8,
          tags: ['대응'],
          audioNormalize: true,
        ),
        HighlightSegment(
          order: 6,
          start: 420,
          end: 480,
          reason: '추가 근거',
          script: '추가 자료와 통계로 확인된 근거입니다',
          score: 7.6,
          tags: ['근거', '출처확인'],
          audioNormalize: true,
        ),
      ];

    controller.buildMultiShortsCandidates(
      maxCandidates: 6,
      minSeconds: 45,
      maxSeconds: 70,
    );

    expect(controller.shortsCandidates.length, greaterThanOrEqualTo(3));
    for (var left = 0; left < controller.shortsCandidates.length; left++) {
      for (
        var right = left + 1;
        right < controller.shortsCandidates.length;
        right++
      ) {
        expect(
          _candidateTemporalOverlapRatio(
            controller.shortsCandidates[left],
            controller.shortsCandidates[right],
          ),
          lessThan(0.72),
        );
      }
    }
  });

  test('multi shorts candidates never mix backend topic groups', () {
    final controller = EditorController(autoStartEngine: false)
      ..duration = 900
      ..segments = const [
        HighlightSegment(
          order: 1,
          start: 0,
          end: 45,
          reason: '허브 핵심',
          score: 9,
          tags: ['Story:Hook'],
          topicId: 1,
        ),
        HighlightSegment(
          order: 2,
          start: 50,
          end: 100,
          reason: '허브 근거',
          score: 8,
          tags: ['Story:Evidence'],
          topicId: 1,
        ),
        HighlightSegment(
          order: 3,
          start: 105,
          end: 150,
          reason: '허브 결론',
          score: 7,
          tags: ['Story:Resolution'],
          topicId: 1,
        ),
        HighlightSegment(
          order: 4,
          start: 500,
          end: 545,
          reason: '교육 핵심',
          score: 9,
          tags: ['Story:Hook'],
          topicId: 2,
        ),
        HighlightSegment(
          order: 5,
          start: 550,
          end: 600,
          reason: '교육 근거',
          score: 8,
          tags: ['Story:Evidence'],
          topicId: 2,
        ),
        HighlightSegment(
          order: 6,
          start: 605,
          end: 650,
          reason: '교육 결론',
          score: 7,
          tags: ['Story:Resolution'],
          topicId: 2,
        ),
      ];

    controller.buildMultiShortsCandidates(
      maxCandidates: 6,
      minSeconds: 90,
      maxSeconds: 160,
    );

    expect(controller.shortsCandidates, isNotEmpty);
    for (final candidate in controller.shortsCandidates) {
      final topics = candidate.segments
          .map((segment) => segment.topicId)
          .where((topicId) => topicId > 0)
          .toSet();
      expect(topics.length, lessThanOrEqualTo(1));
      expect(candidate.issues, isNot(contains('Mixed topics')));
    }
  });

  test('shorts builder fills missing story roles from non adjacent clips', () {
    final controller = EditorController(autoStartEngine: false)
      ..duration = 900
      ..segments = const [
        HighlightSegment(
          order: 1,
          start: 0,
          end: 25,
          reason: '결과부터 보는 핵심 문제',
          script: '오늘 핵심 문제를 먼저 보여드립니다',
          score: 9,
          tags: ['Story:Hook', '유지율'],
          audioNormalize: true,
        ),
        HighlightSegment(
          order: 2,
          start: 40,
          end: 65,
          reason: '반복 인사와 CTA',
          script: '좋아요와 구독 부탁드립니다',
          score: 3,
          tags: ['CTA'],
          audioNormalize: true,
        ),
        HighlightSegment(
          order: 3,
          start: 120,
          end: 145,
          reason: '잡담',
          script: '잠깐 다른 이야기를 덧붙입니다',
          score: 4,
          tags: ['구체성'],
          audioNormalize: true,
        ),
        HighlightSegment(
          order: 4,
          start: 260,
          end: 290,
          reason: '공식 보고서에 따른 근거',
          script: '공식 보고서에 따르면 수치가 확인됐습니다',
          score: 8.5,
          tags: ['Story:Evidence', '근거', '검증팩트'],
          audioNormalize: true,
        ),
        HighlightSegment(
          order: 5,
          start: 520,
          end: 550,
          reason: '시청자에게 미치는 영향',
          script: '주민 피해와 현장 영향이 이어졌습니다',
          score: 8,
          tags: ['Story:Impact', '영향'],
          audioNormalize: true,
        ),
        HighlightSegment(
          order: 6,
          start: 700,
          end: 730,
          reason: '후속 대응과 결론',
          script: '정부는 다음 대응과 결론을 발표했습니다',
          score: 7.8,
          tags: ['Story:Resolution', '대응'],
          audioNormalize: true,
        ),
      ];

    controller.buildMultiShortsCandidates(
      maxCandidates: 4,
      minSeconds: 90,
      maxSeconds: 130,
    );

    final complete = controller.shortsCandidates.firstWhere(
      (candidate) => const [
        'Hook',
        'Evidence',
        'Impact',
        'Resolution',
      ].every(candidate.storyFlow.contains),
    );
    final reasons = complete.segments
        .map((segment) => segment.reason)
        .join(' ');

    expect(complete.completionScore, greaterThanOrEqualTo(90));
    expect(reasons, contains('핵심 문제'));
    expect(reasons, contains('공식 보고서'));
    expect(reasons, contains('미치는 영향'));
    expect(reasons, contains('후속 대응'));
    expect(
      complete.segments.any((segment) => segment.tags.contains('CTA')),
      isFalse,
    );
  });

  test(
    'shorts diagnostics block publish ready state when evidence is missing',
    () {
      final controller = EditorController(autoStartEngine: false)
        ..duration = 240
        ..segments = const [
          HighlightSegment(
            order: 1,
            start: 0,
            end: 52,
            reason: '결과부터 보는 핵심 문제',
            script: '오늘 핵심 문제를 먼저 보여드립니다',
            score: 9,
            tags: ['Story:Hook', '유지율'],
            audioNormalize: true,
          ),
          HighlightSegment(
            order: 2,
            start: 60,
            end: 118,
            reason: '시청자 행동 유도',
            script: '이 내용을 기억하고 다음 편도 봐주세요',
            score: 8,
            tags: ['Story:Close', 'CTA'],
            audioNormalize: true,
          ),
        ];

      controller.buildMultiShortsCandidates(
        maxCandidates: 2,
        minSeconds: 90,
        maxSeconds: 130,
      );

      final missingEvidence = controller.shortsCandidates.firstWhere(
        (candidate) => candidate.issues.contains('Missing evidence'),
      );

      expect(missingEvidence.hasBlockingStoryIssue, isTrue);
      expect(missingEvidence.isPublishReady, isFalse);
      expect(missingEvidence.readinessDetail, 'Missing evidence');
    },
  );

  test('backend story arc tags drive shorts flow scoring', () {
    final controller = EditorController(autoStartEngine: false)
      ..duration = 900
      ..segments = const [
        HighlightSegment(
          order: 1,
          start: 0,
          end: 30,
          reason: 'hook',
          score: 8,
          tags: ['Story:Hook'],
        ),
        HighlightSegment(
          order: 2,
          start: 36,
          end: 66,
          reason: 'context',
          score: 7,
          tags: ['Story:Context'],
        ),
        HighlightSegment(
          order: 3,
          start: 72,
          end: 102,
          reason: 'evidence',
          score: 8,
          tags: ['Story:Evidence'],
        ),
        HighlightSegment(
          order: 4,
          start: 108,
          end: 138,
          reason: 'impact',
          score: 7,
          tags: ['Story:Impact'],
        ),
        HighlightSegment(
          order: 5,
          start: 144,
          end: 174,
          reason: 'resolution',
          score: 7,
          tags: ['Story:Resolution'],
        ),
      ]
      ..selectedSegmentOrder = 1;

    controller.buildMultiShortsCandidates(
      maxCandidates: 5,
      minSeconds: 150,
      maxSeconds: 180,
    );

    final storyCandidate = controller.shortsCandidates.firstWhere(
      (candidate) => const [
        'Hook',
        'Context',
        'Evidence',
        'Impact',
        'Resolution',
      ].every(candidate.storyFlow.contains),
    );
    expect(storyCandidate.storyFlow, [
      'Hook',
      'Context',
      'Evidence',
      'Impact',
      'Resolution',
    ]);
    expect(storyCandidate.storyScore, 100);
    expect(storyCandidate.completionScore, greaterThanOrEqualTo(90));
    expect(storyCandidate.strengths, contains('Story'));
    expect(storyCandidate.strengths, contains('Complete'));
  });

  test('verified fact tag drives news shorts signal scoring', () {
    final controller = EditorController(autoStartEngine: false)
      ..duration = 300
      ..segments = const [
        HighlightSegment(
          order: 1,
          start: 0,
          end: 30,
          reason: '정부 공식 보고서에 따른 검증 팩트',
          script: '국토교통부 공식 보고서에 따르면 피해액은 120억 원입니다',
          score: 8,
          tags: ['뉴스핵심', '검증팩트', '근거'],
        ),
        HighlightSegment(
          order: 2,
          start: 35,
          end: 65,
          reason: '주민 피해 영향',
          score: 7,
          tags: ['영향'],
        ),
        HighlightSegment(
          order: 3,
          start: 70,
          end: 100,
          reason: '정부 대응',
          score: 7,
          tags: ['대응'],
        ),
      ];

    controller.buildMultiShortsCandidates(
      maxCandidates: 4,
      minSeconds: 90,
      maxSeconds: 120,
    );

    final verifiedCandidate = controller.shortsCandidates.firstWhere(
      (candidate) =>
          candidate.segments.any((segment) => segment.tags.contains('검증팩트')),
    );
    expect(verifiedCandidate.strengths, contains('Signals'));
    expect(verifiedCandidate.qualityScore, greaterThanOrEqualTo(70));
  });
}

double _candidateTemporalOverlapRatio(
  ShortsCandidate left,
  ShortsCandidate right,
) {
  final denominator = left.durationSeconds < right.durationSeconds
      ? left.durationSeconds
      : right.durationSeconds;
  if (denominator <= 0) {
    return 0;
  }

  var overlap = 0.0;
  for (final leftSegment in left.segments) {
    for (final rightSegment in right.segments) {
      final start = leftSegment.start > rightSegment.start
          ? leftSegment.start
          : rightSegment.start;
      final end = leftSegment.end < rightSegment.end
          ? leftSegment.end
          : rightSegment.end;
      if (end > start) {
        overlap += end - start;
      }
    }
  }
  return overlap / denominator;
}

Future<ProjectRecoverySnapshot?> _waitForRecoverySnapshot(
  ProjectRecoveryService service,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  ProjectRecoverySnapshot? snapshot;
  do {
    snapshot = await service.readSnapshot();
    if (snapshot != null) {
      return snapshot;
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  } while (DateTime.now().isBefore(deadline));
  return snapshot;
}

class _RecordingApiClient extends ApiClient {
  _RecordingApiClient() : super(baseUrl: 'http://127.0.0.1:1');

  bool renderRequested = false;
  bool batchRenderRequested = false;
  List<HighlightSegment> renderSegments = const [];
  List<Map<String, dynamic>> batchRenderItems = const [];
  String? savedProjectJobId;
  ProjectState? savedProject;

  @override
  Future<ProjectState> saveProject(String jobId, ProjectState project) async {
    savedProjectJobId = jobId;
    savedProject = project;
    return project;
  }

  @override
  Future<void> requestRender(
    String jobId,
    List<HighlightSegment> segments, {
    List<CaptionSegment> captions = const [],
    CaptionRenderStyle? captionStyle,
    String aspectRatio = '16:9',
    bool includeCaptions = false,
    String outputName = 'youtube_highlights.mp4',
  }) async {
    renderRequested = true;
    renderSegments = List<HighlightSegment>.of(segments);
  }

  @override
  Future<void> requestBatchRender(
    String jobId,
    List<Map<String, dynamic>> items, {
    List<CaptionSegment> captions = const [],
    CaptionRenderStyle? captionStyle,
    String aspectRatio = '9:16',
    bool includeCaptions = true,
  }) async {
    batchRenderRequested = true;
    batchRenderItems = List<Map<String, dynamic>>.of(items);
  }

  @override
  Future<JobStatusResponse> getJob(String jobId) async {
    return JobStatusResponse(
      jobId: jobId,
      status: 'rendering',
      stage: 'rendering',
      progress: 1,
      message: 'Rendering',
    );
  }
}

class _ProbeApiClient extends ApiClient {
  _ProbeApiClient() : super(baseUrl: 'http://127.0.0.1:1');

  @override
  Future<MediaProbeInfo> probeLocalMedia(String path) async {
    return MediaProbeInfo.fromJson({
      'path': path,
      'filename': 'cached-preview-source.mp4',
      'duration': 3035.767,
      'can_analyze': true,
      'is_mxf': false,
      'audio_stream_count': 1,
      'audio_channel_count': 2,
    });
  }
}

class _ReadyEngineService extends LocalEngineService {
  @override
  Future<LocalEngineState> ensureRunning({int port = 8000}) async {
    return const LocalEngineState(
      status: 'running',
      message: 'ready',
      isRunning: true,
      canStart: true,
    );
  }

  @override
  Future<void> dispose() async {}
}
