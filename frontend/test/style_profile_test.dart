import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_editor_app/models/job_models.dart';

void main() {
  test('style profile parses backend reference learning format', () {
    final profile = StyleProfile.fromJson({
      'style_id': 'style-1',
      'name': 'Company Style',
      'status': 'ready',
      'message': 'done',
      'progress': 100,
      'source_count': 6,
      'ready_source_count': 5,
      'pace': 'fast',
      'average_cut_seconds': 4.2,
      'hook_window_seconds': 10.5,
      'silence_aggressiveness': 0.82,
      'visual_change_sensitivity': 0.71,
      'target_segment_seconds_min': 12,
      'target_segment_seconds_ideal': 24,
      'target_segment_seconds_max': 38,
      'prefer_news_structure': true,
      'prefer_shorts_structure': false,
      'transition_style': 'hard_cut',
      'scoring_weights': {'hook': 1.4, 'style_duration': 1.2},
      'sources': [
        {
          'label': 'ref.mp4',
          'kind': 'file',
          'duration': 600,
          'scene_count': 120,
          'average_cut_seconds': 4.2,
          'silence_ratio': 0.1,
        },
      ],
    });

    expect(profile.isReady, isTrue);
    expect(profile.readySourceCount, 5);
    expect(profile.averageCutSeconds, 4.2);
    expect(profile.scoringWeights['hook'], 1.4);
    expect(profile.sources.single.label, 'ref.mp4');
  });
}
