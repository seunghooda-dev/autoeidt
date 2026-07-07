from app.services.llm_service import fallback_highlights


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
