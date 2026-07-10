from app.services.ffmpeg_service import _portrait_reframe_filters
from app.services.smart_reframe import (
    FocusSample,
    _choose_face,
    _deduplicate_faces,
    _focus_from_samples,
    _focus_keyframes_from_samples,
    _sample_times,
)


def test_face_choice_prefers_prominent_continuous_speaker() -> None:
    chosen = _choose_face(
        [(30, 50, 80, 80), (390, 80, 180, 180)],
        frame_width=640,
        frame_height=360,
        previous_x=0.78,
    )

    assert chosen is not None
    assert chosen.x > 0.7


def test_frontal_and_profile_detections_are_deduplicated() -> None:
    faces = _deduplicate_faces(
        [(100, 60, 120, 120), (108, 65, 112, 115), (420, 70, 80, 80)]
    )

    assert len(faces) == 2
    assert faces[0] == (100, 60, 120, 120)


def test_focus_aggregation_tracks_speaker_and_reports_confidence() -> None:
    focus_x, focus_y, confidence = _focus_from_samples(
        [
            FocusSample(x=0.72, y=0.32, weight=0.4),
            FocusSample(x=0.74, y=0.34, weight=0.5),
            FocusSample(x=0.70, y=0.33, weight=0.4),
        ],
        sample_count=4,
    )

    assert focus_x > 0.65
    assert 0.25 < focus_y < 0.4
    assert confidence > 0.6


def test_portrait_filter_uses_detected_focus_and_upper_third_headroom() -> None:
    filters = _portrait_reframe_filters({"focus_x": 0.72, "focus_y": 0.31})
    joined = ",".join(filters)

    assert "scale=1080:1920" in joined
    assert "iw*(0.720000)-ow/2" in joined
    assert "ih*(0.310000)-oh*0.38" in joined


def test_portrait_filter_emits_fast_transitions_between_speaker_keyframes() -> None:
    filters = _portrait_reframe_filters(
        {
            "focus_x": 0.5,
            "focus_y": 0.42,
            "focus_keyframes": [
                {"time": 0.0, "x": 0.2, "y": 0.35},
                {"time": 2.0, "x": 0.92, "y": 0.34},
            ],
        }
    )
    crop = next(item for item in filters if item.startswith("crop="))

    assert "if(lt(t" in crop
    assert "0.720000" in crop
    assert "clip((t-" in crop
    assert any("fillborders" in item for item in filters)


def test_focus_keyframes_drop_redundant_positions_and_cover_clip_edges() -> None:
    keyframes = _focus_keyframes_from_samples(
        [
            (0.4, FocusSample(x=0.7, y=0.33, weight=0.4)),
            (1.2, FocusSample(x=0.71, y=0.34, weight=0.4)),
            (2.8, FocusSample(x=0.25, y=0.31, weight=0.5)),
        ],
        duration=4.0,
    )

    assert keyframes[0]["time"] == 0.0
    assert keyframes[-1]["time"] == 4.0
    assert len(keyframes) == 4


def test_sampling_is_bounded_for_long_broadcast_segments() -> None:
    samples = _sample_times(120.0, 420.0, max_samples=24)

    assert len(samples) == 24
    assert samples[0] > 120
    assert samples[-1] < 420
