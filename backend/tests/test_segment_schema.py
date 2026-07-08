from app.schemas import CaptionSegment, CaptionStyle, HighlightSegment, ProjectState


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


def test_timeline_payloads_snap_to_30p_non_drop_grid() -> None:
    segment = HighlightSegment(
        order=1,
        start=1.001,
        end=2.049,
        reason="frame grid",
        audio_start=3.016,
        audio_end=4.019,
    )
    caption = CaptionSegment(order=1, start=5.012, end=6.049, text="caption")
    project = ProjectState(
        duration=60,
        timeline_frame_rate=29.97,
        timeline_timecode_mode="drop",
        mark_in=12.516,
        mark_out=58.019,
        timeline_markers=[{"id": 1, "seconds": 7.018, "label": "Snap"}],
        shorts_candidates=[
            {
                "id": 1,
                "label": "Shorts 01",
                "segments": [
                    {
                        "order": 2,
                        "start": 8.019,
                        "end": 9.049,
                        "reason": "shorts",
                    }
                ],
            }
        ],
    )

    assert segment.start == 1.0
    assert segment.end == 2.033333
    assert segment.audio_start == 3.0
    assert segment.audio_end == 4.033333
    assert caption.start == 5.0
    assert caption.end == 6.033333
    assert project.timeline_frame_rate == 30.0
    assert project.timeline_timecode_mode == "non_drop"
    assert project.mark_in == 12.5
    assert project.mark_out == 58.033333
    assert project.timeline_markers[0].seconds == 7.033333
    assert project.shorts_candidates[0]["segments"][0]["start"] == 8.033333
    assert project.shorts_candidates[0]["segments"][0]["end"] == 9.033333


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
