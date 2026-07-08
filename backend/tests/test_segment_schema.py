from app.schemas import CaptionStyle, HighlightSegment


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
        audio_channel_2_enabled=False,
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
    assert segment.audio_channel_1_enabled is True
    assert segment.audio_channel_2_enabled is False


def test_caption_style_clamps_unsafe_values() -> None:
    style = CaptionStyle(
        font_size=200,
        outline=20,
        shadow=20,
        alignment=99,
        margin_v=999,
    )

    assert style.font_size == 72
    assert style.outline == 8
    assert style.shadow == 8
    assert style.alignment == 9
    assert style.margin_v == 360
