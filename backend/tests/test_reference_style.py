from app.services.editing_skills import select_highlights_with_skills
from app.services.reference_style import build_style_profile


def test_reference_style_profile_aggregates_cut_pace() -> None:
    profile = build_style_profile(
        style_id="style-test",
        name="Company Style",
        sources=[
            {
                "label": "ref1.mp4",
                "kind": "file",
                "duration": 600,
                "scene_count": 160,
                "scene_rate_per_minute": 16,
                "average_cut_seconds": 3.8,
                "median_cut_seconds": 3.5,
                "silence_ratio": 0.08,
                "speech_ratio": 0.92,
            },
            {
                "label": "ref2.mp4",
                "kind": "file",
                "duration": 540,
                "scene_count": 120,
                "scene_rate_per_minute": 13.3,
                "average_cut_seconds": 4.2,
                "median_cut_seconds": 4.0,
                "silence_ratio": 0.12,
                "speech_ratio": 0.88,
            },
        ],
    )

    assert profile["status"] == "ready"
    assert profile["pace"] == "fast"
    assert profile["ready_source_count"] == 2
    assert profile["target_segment_seconds_max"] <= 38
    assert profile["silence_aggressiveness"] > 0.7
    assert profile["scoring_weights"]["hook"] >= 1.0


def test_style_profile_biases_highlight_selection_toward_reference_length() -> None:
    transcript = [
        {"start": 0.0, "end": 8.0, "text": "바로 결과부터 보여드리겠습니다 핵심 문제입니다"},
        {"start": 8.0, "end": 16.0, "text": "첫 번째 근거는 통계 자료에 따르면 분명합니다"},
        {"start": 16.0, "end": 24.0, "text": "두 번째 영향은 시민 피해가 커진다는 점입니다"},
        {"start": 24.0, "end": 32.0, "text": "회사 측은 공식 입장을 내고 대응했습니다"},
        {"start": 32.0, "end": 60.0, "text": "이후에는 반복되는 배경 설명과 마무리 인사입니다"},
    ]
    style_profile = {
        "pace": "fast",
        "hook_window_seconds": 10,
        "target_segment_seconds_min": 8,
        "target_segment_seconds_ideal": 16,
        "target_segment_seconds_max": 24,
        "prefer_news_structure": True,
        "scoring_weights": {
            "style_duration": 1.2,
            "hook": 1.4,
            "information_density": 1.1,
            "news_structure": 1.2,
        },
    }

    highlights = select_highlights_with_skills(
        transcript,
        duration=60,
        target_min_seconds=16,
        target_max_seconds=36,
        style_profile=style_profile,
    )

    assert highlights
    assert any("레퍼런스" in tag for item in highlights for tag in item["tags"])
    assert all(item["end"] - item["start"] <= 24.1 for item in highlights)
