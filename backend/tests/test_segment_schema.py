from app.schemas import CaptionStyle, HighlightSegment, ProjectState


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


def test_project_state_accepts_render_settings() -> None:
    project = ProjectState(
        name="shorts project",
        original_path="C:/media/source.mxf",
        duration=120,
        timeline_frame_rate=29.97,
        timeline_timecode_mode="drop",
        include_captions=False,
        caption_style_preset="shorts",
        export_aspect_ratio="9:16",
        mark_in=12.5,
        mark_out=58.0,
        timeline_markers=[
            {
                "id": 1,
                "seconds": -3.0,
                "label": "Hook",
                "color": "cyan",
                "enabled": False,
            }
        ],
        shorts_candidates=[
            {
                "id": 1,
                "label": "Hook 01",
                "reason": "fast hook",
                "segments": [],
                "quality_score": 76.0,
            }
        ],
        selected_shorts_id=1,
    )

    assert project.include_captions is False
    assert project.original_path == "C:/media/source.mxf"
    assert project.timeline_frame_rate == 30.0
    assert project.timeline_timecode_mode == "non_drop"
    assert project.caption_style_preset == "shorts"
    assert project.export_aspect_ratio == "9:16"
    assert project.mark_in == 12.5
    assert project.mark_out == 58.0
    assert project.timeline_markers[0].seconds == 0.0
    assert project.timeline_markers[0].label == "Hook"
    assert project.timeline_markers[0].enabled is False
    assert project.shorts_candidates[0]["label"] == "Hook 01"
    assert project.selected_shorts_id == 1
