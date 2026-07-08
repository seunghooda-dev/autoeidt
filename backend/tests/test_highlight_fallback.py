from app.services.llm_service import fallback_highlights
from app.services.hybrid_cut import attach_script_preview
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


def test_missing_stt_fallback_is_not_used_as_script_preview() -> None:
    transcript = fallback_transcript(90)

    preview = attach_script_preview({"start": 0, "end": 45}, transcript)

    assert preview == ""
