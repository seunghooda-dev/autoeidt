from app.schemas import CaptionSegment, CaptionStyle, HighlightSegment, ProjectState
from app.tasks import _normalize_highlights


def test_highlight_segment_accepts_track_controls() -> None:
    segment = HighlightSegment(
        order=1,
        start=1,
        end=5,
        reason="test",
        video_enabled=False,
        video_opacity=4,
        video_scale=7,
        video_position_x=-3,
        video_position_y=3,
        video_rotation=270,
        motion_keyframes=[
            {
                "time": -2,
                "opacity": 4,
                "scale": 8,
                "position_x": -3,
                "position_y": 3,
                "rotation": 270,
            },
            {"time": 2.019, "opacity": 0.5, "scale": 1.4},
        ],
        video_fade_in=20,
        video_fade_out=20,
        color_brightness=1,
        color_contrast=5,
        color_saturation=5,
        focus_x=2,
        focus_y=-1,
        focus_confidence=4,
        focus_keyframes=[
            {"time": -2, "x": 4, "y": -1},
            {"time": 3, "x": 0.7, "y": 0.3},
        ],
        topic_id=-3,
        audio_volume=3,
        audio_gain_keyframes=[
            {"time": 2.019, "volume": 3},
            {"time": -1, "volume": -2},
            {"time": 2.018, "volume": 0.75},
            {"time": "invalid", "volume": 1},
        ],
        audio_pan=-2,
        audio_normalize=True,
        audio_loudness_target=-99,
        audio_channel_2_enabled=False,
        audio_source_channel_left=99,
        audio_source_channel_right=-5,
        transition_type="unsupported",
        transition_duration=99,
    )

    assert segment.video_enabled is False
    assert segment.video_opacity == 1.0
    assert segment.video_scale == 3.0
    assert segment.video_position_x == -1.0
    assert segment.video_position_y == 1.0
    assert segment.video_rotation == 180.0
    assert segment.motion_keyframes[0] == {
        "time": 0.0,
        "opacity": 1.0,
        "scale": 3.0,
        "position_x": -1.0,
        "position_y": 1.0,
        "rotation": 180.0,
    }
    assert segment.motion_keyframes[1]["time"] == 2.033333
    assert segment.video_fade_in == 10.0
    assert segment.video_fade_out == 10.0
    assert segment.color_brightness == 0.3
    assert segment.color_contrast == 1.8
    assert segment.color_saturation == 2.0
    assert segment.focus_x == 1.0
    assert segment.focus_y == 0.0
    assert segment.focus_confidence == 1.0
    assert segment.focus_keyframes[0] == {"time": 0.0, "x": 1.0, "y": 0.0}
    assert segment.topic_id == 0
    assert segment.audio_volume == 2.0
    assert segment.audio_gain_keyframes == [
        {"time": 0.0, "volume": 0.0},
        {"time": 2.033333, "volume": 0.75},
    ]
    assert segment.audio_pan == -1.0
    assert segment.audio_normalize is True
    assert segment.audio_loudness_target == -24.0
    assert segment.audio_channel_1_enabled is True
    assert segment.audio_channel_2_enabled is False
    assert segment.audio_source_channel_left == 64
    assert segment.audio_source_channel_right == 1
    assert segment.transition_type == "cut"
    assert segment.transition_duration == 3.0


def test_render_normalization_preserves_supported_clip_transitions() -> None:
    normalized = _normalize_highlights(
        [
            {
                "order": 1,
                "start": 0,
                "end": 4,
                "reason": "opener",
                "transition_type": "dip_black",
                "transition_duration": 1,
            },
            {
                "order": 2,
                "start": 10,
                "end": 14,
                "reason": "answer",
                "transition_type": "cross_dissolve",
                "transition_duration": 0.45,
            },
        ],
        duration=30,
        preserve_order=True,
    )

    assert normalized[0]["transition_type"] == "cut"
    assert normalized[0]["transition_duration"] == 0
    assert normalized[1]["transition_type"] == "cross_dissolve"
    assert normalized[1]["transition_duration"] == 0.466667


def test_render_normalization_preserves_motion_and_opacity() -> None:
    normalized = _normalize_highlights(
        [
            {
                "start": 1,
                "end": 5,
                "reason": "motion",
                "video_opacity": 0.62,
                "video_scale": 1.4,
                "video_position_x": -0.35,
                "video_position_y": 0.2,
                "video_rotation": 14.5,
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
                        "time": 3,
                        "opacity": 0.6,
                        "scale": 1.8,
                        "position_x": 0.2,
                        "position_y": -0.1,
                        "rotation": 12,
                    },
                ],
            }
        ],
        duration=10,
        preserve_order=True,
    )

    assert normalized[0]["video_opacity"] == 0.62
    assert normalized[0]["video_scale"] == 1.4
    assert normalized[0]["video_position_x"] == -0.35
    assert normalized[0]["video_position_y"] == 0.2
    assert normalized[0]["video_rotation"] == 14.5
    assert len(normalized[0]["motion_keyframes"]) == 2
    assert normalized[0]["motion_keyframes"][1]["scale"] == 1.8


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
        locked_video_tracks=[4, 4, 1, 9],
        hidden_video_tracks=[3, 8],
        locked_audio_tracks=[8, 8, 2, 10],
        muted_audio_tracks=[7, 1, 9],
        solo_audio_tracks=[1, 7, 7, 9],
        timeline_markers=[{"id": 1, "seconds": 7.018, "label": "Snap"}],
        video_overlays=[
            {
                "id": "v2-1",
                "source_path": "C:/media/broll.mov",
                "source_name": "broll.mov",
                "timeline_start": 10.019,
                "timeline_end": 16.049,
                "source_start": 2.016,
                "source_end": 8.049,
                "scale": 4.0,
                "position_x": -2.0,
                "audio_volume": 4.0,
                "audio_pan": -2.0,
                "audio_fade_in": 12.0,
                "audio_fade_out": -1.0,
                "audio_gain_keyframes": [
                    {"time": 3.019, "volume": 3.0},
                    {"time": 1.017, "volume": -1.0},
                    {"time": 1.018, "volume": 0.4},
                ],
                "video_track": 9,
                "audio_track": 20,
            }
        ],
        audio_clips=[
            {
                "id": "audio-1",
                "source_path": "C:/media/music.wav",
                "source_name": "music.wav",
                "timeline_start": 20.019,
                "timeline_end": 30.049,
                "source_start": 1.016,
                "source_end": 11.049,
                "track": 99,
                "volume": 4.0,
                "pan": 2.0,
                "fade_in": 12.0,
                "fade_out": -1.0,
                "gain_keyframes": [
                    {"time": 4.019, "volume": 1.4},
                    {"time": -2, "volume": -1},
                ],
            }
        ],
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
    assert project.video_overlays[0].timeline_start == 10.033333
    assert project.video_overlays[0].timeline_end == 16.033333
    assert project.video_overlays[0].source_start == 2.0
    assert project.video_overlays[0].source_end == 8.033333
    assert project.video_overlays[0].scale == 1.0
    assert project.video_overlays[0].position_x == -1.0
    assert project.video_overlays[0].audio_volume == 2.0
    assert project.video_overlays[0].audio_pan == -1.0
    assert project.video_overlays[0].audio_fade_in == 10.0
    assert project.video_overlays[0].audio_fade_out == 0.0
    assert project.video_overlays[0].audio_gain_keyframes == [
        {"time": 1.033333, "volume": 0.4},
        {"time": 3.033333, "volume": 2.0},
    ]
    assert project.video_overlays[0].video_track == 4
    assert project.video_overlays[0].audio_track == 8
    assert project.active_video_track_count == 4
    assert project.active_audio_track_count == 8
    assert project.locked_video_tracks == [4]
    assert project.hidden_video_tracks == [3]
    assert project.locked_audio_tracks == [8]
    assert project.muted_audio_tracks == [7]
    assert project.solo_audio_tracks == [1, 7]
    assert project.audio_clips[0].timeline_start == 20.033333
    assert project.audio_clips[0].track == 8
    assert project.audio_clips[0].volume == 2.0
    assert project.audio_clips[0].pan == 1.0
    assert project.audio_clips[0].fade_in == 10.0
    assert project.audio_clips[0].fade_out == 0.0
    assert project.audio_clips[0].gain_keyframes == [
        {"time": 0.0, "volume": 0.0},
        {"time": 4.033333, "volume": 1.4},
    ]
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
        transcript=[{"start": 1.01, "end": 2.04, "text": "full transcript"}],
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
    assert project.selected_export_profiles == ["9:16"]
    assert project.transcript[0].text == "full transcript"
    assert project.transcript[0].start == 1.0
    assert project.mark_in == 12.5
    assert project.mark_out == 58.0
    assert project.timeline_markers[0].seconds == 0.0
    assert project.timeline_markers[0].label == "Hook"
    assert project.timeline_markers[0].enabled is False
    assert project.shorts_candidates[0]["label"] == "Hook 01"
    assert project.selected_shorts_id == 1
