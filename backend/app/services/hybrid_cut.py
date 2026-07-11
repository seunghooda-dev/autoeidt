from dataclasses import asdict
from pathlib import Path
from typing import Any

from app.config import get_settings
from app.services.ffmpeg_service import SilenceRange, detect_scene_changes


def overlaps(a_start: float, a_end: float, b_start: float, b_end: float) -> bool:
    return max(a_start, b_start) < min(a_end, b_end)


def has_visual_motion(
    video_path: Path,
    start: float,
    end: float,
    threshold: float | None = None,
) -> bool:
    settings = get_settings()
    threshold = threshold or settings.visual_motion_threshold
    try:
        import cv2
        import numpy as np
    except Exception:
        return False

    cap = cv2.VideoCapture(str(video_path))
    if not cap.isOpened():
        return False

    sample_step = 0.5
    cursor = max(start, 0.0)
    previous_gray = None
    motion_scores: list[float] = []

    while cursor <= end:
        cap.set(cv2.CAP_PROP_POS_MSEC, cursor * 1000)
        ok, frame = cap.read()
        if not ok:
            cursor += sample_step
            continue

        frame = cv2.resize(frame, (320, 180))
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        if previous_gray is not None:
            flow = cv2.calcOpticalFlowFarneback(
                previous_gray,
                gray,
                None,
                0.5,
                3,
                15,
                3,
                5,
                1.2,
                0,
            )
            magnitude, _ = cv2.cartToPolar(flow[..., 0], flow[..., 1])
            motion_scores.append(float(np.mean(magnitude)))
        previous_gray = gray
        cursor += sample_step

    cap.release()
    return bool(motion_scores and max(motion_scores) >= threshold)


def build_protected_silences(
    video_path: Path,
    silence_ranges: list[SilenceRange],
    scene_points: list[float] | None = None,
) -> list[SilenceRange]:
    settings = get_settings()
    scene_points = scene_points if scene_points is not None else detect_scene_changes(
        video_path,
        settings.scene_change_threshold,
    )

    protected: list[SilenceRange] = []
    for silence in silence_ranges:
        has_scene_change = any(silence.start <= point <= silence.end for point in scene_points)
        if has_scene_change or has_visual_motion(video_path, silence.start, silence.end):
            protected.append(silence)
    return protected


def _subtract_interval(
    ranges: list[tuple[float, float]],
    cut_start: float,
    cut_end: float,
    min_piece_seconds: float,
) -> list[tuple[float, float]]:
    output: list[tuple[float, float]] = []
    for start, end in ranges:
        if not overlaps(start, end, cut_start, cut_end):
            output.append((start, end))
            continue
        if cut_start - start >= min_piece_seconds:
            output.append((start, cut_start))
        if end - cut_end >= min_piece_seconds:
            output.append((cut_end, end))
    return output


def attach_script_preview(
    segment: dict[str, Any],
    transcript: list[dict[str, Any]],
) -> str:
    for item in transcript:
        if item.get("source") == "fallback_stt":
            continue
        if overlaps(
            float(segment["start"]),
            float(segment["end"]),
            float(item["start"]),
            float(item["end"]),
        ):
            return str(item.get("text", "")).strip()
    return ""


def _sample_motion_keyframe(
    keyframes: list[dict[str, float]],
    time: float,
) -> dict[str, float]:
    if time <= keyframes[0]["time"]:
        return dict(keyframes[0])
    if time >= keyframes[-1]["time"]:
        return dict(keyframes[-1])
    for index in range(len(keyframes) - 1):
        left = keyframes[index]
        right = keyframes[index + 1]
        if time > right["time"]:
            continue
        duration = max(1 / 30, right["time"] - left["time"])
        progress = max(0.0, min((time - left["time"]) / duration, 1.0))
        return {
            "time": time,
            **{
                field: left[field] + (right[field] - left[field]) * progress
                for field in (
                    "opacity",
                    "scale",
                    "position_x",
                    "position_y",
                    "rotation",
                )
            },
        }
    return dict(keyframes[-1])


def _remap_motion_keyframes(
    highlight: dict[str, Any],
    piece_start: float,
    piece_end: float,
) -> list[dict[str, float]]:
    raw = highlight.get("motion_keyframes", [])
    if not isinstance(raw, list) or not raw:
        return []
    speed = max(0.25, min(float(highlight.get("playback_speed", 1.0)), 4.0))
    highlight_start = float(highlight["start"])
    trim_start = max(0.0, (piece_start - highlight_start) / speed)
    trim_end = max(trim_start, (piece_end - highlight_start) / speed)
    keyframes: list[dict[str, float]] = []
    for item in raw:
        if not isinstance(item, dict):
            continue
        try:
            keyframes.append(
                {
                    "time": max(0.0, float(item.get("time", 0.0))),
                    "opacity": max(0.0, min(float(item.get("opacity", 1.0)), 1.0)),
                    "scale": max(1.0, min(float(item.get("scale", 1.0)), 3.0)),
                    "position_x": max(
                        -1.0, min(float(item.get("position_x", 0.0)), 1.0)
                    ),
                    "position_y": max(
                        -1.0, min(float(item.get("position_y", 0.0)), 1.0)
                    ),
                    "rotation": max(
                        -180.0, min(float(item.get("rotation", 0.0)), 180.0)
                    ),
                }
            )
        except (TypeError, ValueError):
            continue
    if not keyframes:
        return []
    keyframes.sort(key=lambda item: item["time"])
    output = [_sample_motion_keyframe(keyframes, trim_start)]
    output.extend(
        dict(item)
        for item in keyframes
        if trim_start < item["time"] < trim_end
    )
    output.append(_sample_motion_keyframe(keyframes, trim_end))
    for item in output:
        item["time"] = round(max(0.0, item["time"] - trim_start), 6)
        for field in item.keys() - {"time"}:
            item[field] = round(item[field], 6)
    return output


def refine_highlights_with_hybrid_cut(
    highlights: list[dict[str, Any]],
    silence_ranges: list[SilenceRange],
    protected_silences: list[SilenceRange],
    transcript: list[dict[str, Any]],
    min_piece_seconds: float = 2.0,
) -> list[dict[str, Any]]:
    protected_pairs = [(item.start, item.end) for item in protected_silences]
    refined: list[dict[str, Any]] = []

    for highlight in highlights:
        ranges = [(float(highlight["start"]), float(highlight["end"]))]
        for silence in silence_ranges:
            is_protected = any(
                overlaps(silence.start, silence.end, start, end)
                for start, end in protected_pairs
            )
            if is_protected:
                continue
            ranges = _subtract_interval(
                ranges,
                silence.start,
                silence.end,
                min_piece_seconds,
            )

        for start, end in ranges:
            if end - start < min_piece_seconds:
                continue
            refined.append(
                {
                    "order": 0,
                    "start": round(start, 1),
                    "end": round(end, 1),
                    "reason": str(highlight.get("reason", "AI 추천 구간")),
                    "script": "",
                    "source": str(highlight.get("source", "ai")),
                    "video_enabled": bool(highlight.get("video_enabled", True)),
                    "video_opacity": float(highlight.get("video_opacity", 1.0)),
                    "video_scale": float(highlight.get("video_scale", 1.0)),
                    "video_position_x": float(highlight.get("video_position_x", 0.0)),
                    "video_position_y": float(highlight.get("video_position_y", 0.0)),
                    "video_rotation": float(highlight.get("video_rotation", 0.0)),
                    "motion_keyframes": _remap_motion_keyframes(
                        highlight,
                        start,
                        end,
                    ),
                    "video_fade_in": float(highlight.get("video_fade_in", 0.0)),
                    "video_fade_out": float(highlight.get("video_fade_out", 0.0)),
                    "color_brightness": float(highlight.get("color_brightness", 0.0)),
                    "color_contrast": float(highlight.get("color_contrast", 1.0)),
                    "color_saturation": float(highlight.get("color_saturation", 1.0)),
                    "focus_x": float(highlight.get("focus_x", 0.5)),
                    "focus_y": float(highlight.get("focus_y", 0.42)),
                    "focus_confidence": float(highlight.get("focus_confidence", 0.0)),
                    "focus_keyframes": list(highlight.get("focus_keyframes", [])),
                    "topic_id": int(highlight.get("topic_id", 0) or 0),
                    "playback_speed": float(highlight.get("playback_speed", 1.0)),
                    "audio_pan": float(highlight.get("audio_pan", 0.0)),
                    "audio_normalize": bool(highlight.get("audio_normalize", False)),
                    "audio_loudness_target": float(
                        highlight.get("audio_loudness_target", -14.0)
                    ),
                    "audio_channel_1_enabled": bool(
                        highlight.get("audio_channel_1_enabled", True)
                    ),
                    "audio_channel_2_enabled": bool(
                        highlight.get("audio_channel_2_enabled", True)
                    ),
                    "audio_source_channel_left": int(
                        highlight.get("audio_source_channel_left", 1) or 1
                    ),
                    "audio_source_channel_right": int(
                        highlight.get("audio_source_channel_right", 2) or 2
                    ),
                    "score": float(highlight.get("score", 0.0)),
                    "tags": list(highlight.get("tags", [])),
                }
            )

    refined.sort(key=lambda item: float(item["start"]))
    for index, segment in enumerate(refined, start=1):
        segment["order"] = index
        segment["script"] = attach_script_preview(segment, transcript)
    return refined


def silence_ranges_to_dicts(items: list[SilenceRange]) -> list[dict[str, float]]:
    return [asdict(item) for item in items]
