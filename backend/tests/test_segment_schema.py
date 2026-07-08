from app.schemas import HighlightSegment


def test_highlight_segment_accepts_track_controls() -> None:
    segment = HighlightSegment(
        order=1,
        start=1,
        end=5,
        reason="test",
        video_enabled=False,
        audio_volume=3,
        audio_pan=-2,
    )

    assert segment.video_enabled is False
    assert segment.audio_volume == 2.0
    assert segment.audio_pan == -1.0
