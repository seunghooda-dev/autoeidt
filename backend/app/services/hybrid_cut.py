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
        if overlaps(
            float(segment["start"]),
            float(segment["end"]),
            float(item["start"]),
            float(item["end"]),
        ):
            return str(item.get("text", "")).strip()
    return ""


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
                }
            )

    refined.sort(key=lambda item: float(item["start"]))
    for index, segment in enumerate(refined, start=1):
        segment["order"] = index
        segment["script"] = attach_script_preview(segment, transcript)
    return refined


def silence_ranges_to_dicts(items: list[SilenceRange]) -> list[dict[str, float]]:
    return [asdict(item) for item in items]
