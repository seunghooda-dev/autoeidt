from app.services.ffmpeg_service import SilenceRange
from app.services.llm_service import fallback_highlights, fallback_review_highlights
from app.services.hybrid_cut import (
    attach_script_preview,
    refine_highlights_with_hybrid_cut,
)
from app.services.stt_service import fallback_transcript
from app.tasks import _captions_from_transcript


def test_fallback_highlights_returns_chronological_segments() -> None:
    transcript = [
        {"start": 0.0, "end": 30.0, "text": "도입"},
        {"start": 30.0, "end": 60.0, "text": "핵심 문제 설명"},
        {"start": 60.0, "end": 90.0, "text": "해결 방법과 결론"},
    ]

    highlights = fallback_highlights(transcript, duration=90.0)

    assert highlights
    assert highlights == sorted(highlights, key=lambda item: item["start"])
    assert all(item["end"] > item["start"] for item in highlights)
    assert all("score" in item for item in highlights)
    assert all(item.get("tags") for item in highlights)


def test_missing_stt_fallback_does_not_generate_fake_content_captions() -> None:
    transcript = fallback_transcript(860)

    assert transcript
    assert all(item["source"] == "fallback_stt" for item in transcript)
    assert "OPENAI_API_KEY" not in " ".join(item["text"] for item in transcript)
    assert _captions_from_transcript(transcript) == []


def test_missing_stt_fallback_returns_review_segments_near_target_duration() -> None:
    transcript = fallback_transcript(860)

    highlights = fallback_highlights(transcript, duration=860)

    assert len(highlights) >= 3
    assert highlights == sorted(highlights, key=lambda item: item["start"])
    assert all(item["source"] == "fallback-review" for item in highlights)
    assert sum(item["end"] - item["start"] for item in highlights) >= 150


def test_missing_stt_fallback_prefers_audio_activity_ranges() -> None:
    silences = [
        SilenceRange(start=0.0, end=35.0, duration=35.0),
        SilenceRange(start=75.0, end=120.0, duration=45.0),
        SilenceRange(start=165.0, end=190.0, duration=25.0),
        SilenceRange(start=225.0, end=240.0, duration=15.0),
    ]

    highlights = fallback_review_highlights(
        duration=240,
        target_min_seconds=90,
        target_max_seconds=120,
        silence_ranges=silences,
    )

    assert highlights
    assert all(item["source"] == "fallback-audio-review" for item in highlights)
    assert highlights == sorted(highlights, key=lambda item: item["start"])
    assert all("오디오활성" in item["tags"] for item in highlights)
    total_duration = sum(item["end"] - item["start"] for item in highlights)
    silence_overlap = sum(
        max(0.0, min(item["end"], silence.end) - max(item["start"], silence.start))
        for item in highlights
        for silence in silences
    )
    assert total_duration > 0
    assert silence_overlap / total_duration < 0.2


def test_missing_stt_fallback_uses_scene_changes_inside_audio_activity() -> None:
    silences = [
        SilenceRange(start=0.0, end=35.0, duration=35.0),
        SilenceRange(start=75.0, end=120.0, duration=45.0),
        SilenceRange(start=165.0, end=190.0, duration=25.0),
        SilenceRange(start=225.0, end=240.0, duration=15.0),
    ]

    highlights = fallback_review_highlights(
        duration=240,
        target_min_seconds=90,
        target_max_seconds=120,
        silence_ranges=silences,
        scene_points=[130.0, 140.0, 150.0],
    )

    assert highlights
    assert any(
        item["source"] == "fallback-audio-visual-review"
        for item in highlights
    )
    visual = next(
        item
        for item in highlights
        if item["source"] == "fallback-audio-visual-review"
    )
    assert "화면전환" in visual["tags"]
    assert visual["start"] <= 140 <= visual["end"]


def test_missing_stt_fallback_is_not_used_as_script_preview() -> None:
    transcript = fallback_transcript(90)

    preview = attach_script_preview({"start": 0, "end": 45}, transcript)

    assert preview == ""


def test_hybrid_cut_remaps_motion_keyframes_to_each_remaining_piece() -> None:
    refined = refine_highlights_with_hybrid_cut(
        [
            {
                "start": 0,
                "end": 10,
                "reason": "animated",
                "motion_keyframes": [
                    {
                        "time": 0,
                        "opacity": 1,
                        "scale": 1,
                        "position_x": 0,
                        "position_y": 0,
                        "rotation": 0,
                    },
                    {
                        "time": 10,
                        "opacity": 0.5,
                        "scale": 2,
                        "position_x": 0.5,
                        "position_y": -0.5,
                        "rotation": 20,
                    },
                ],
            }
        ],
        [SilenceRange(start=4, end=6, duration=2)],
        [],
        [],
        min_piece_seconds=2,
    )

    assert len(refined) == 2
    first, second = refined
    assert first["motion_keyframes"][0]["time"] == 0
    assert first["motion_keyframes"][-1]["time"] == 4
    assert first["motion_keyframes"][-1]["scale"] == 1.4
    assert second["motion_keyframes"][0]["time"] == 0
    assert second["motion_keyframes"][0]["scale"] == 1.6
    assert second["motion_keyframes"][-1]["time"] == 4
    assert second["motion_keyframes"][-1]["scale"] == 2
