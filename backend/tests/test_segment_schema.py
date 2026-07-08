from app.schemas import HighlightSegment


def test_highlight_segment_accepts_track_controls() -> None:
    segment = HighlightSegment(
        order=1,
        start=1,
        end=5,
        reason="test",
        video_enabled=False,
        video_fade_in=20,
        video_fade_out=20,
        color_brightness=1,
        color_contrast=5,
        color_saturation=5,
        audio_volume=3,
        audio_pan=-2,
        audio_normalize=True,
    )

    assert segment.video_enabled is False
    assert segment.video_fade_in == 10.0
    assert segment.video_fade_out == 10.0
    assert segment.color_brightness == 0.3
    assert segment.color_contrast == 1.8
    assert segment.color_saturation == 2.0
    assert segment.audio_volume == 2.0
    assert segment.audio_pan == -1.0
    assert segment.audio_normalize is True
