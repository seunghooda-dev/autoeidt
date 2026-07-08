from __future__ import annotations

import statistics
import subprocess
import sys
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

from app.config import get_settings
from app.services.ffmpeg_service import (
    detect_scene_changes,
    detect_silence,
    extract_audio,
    probe_duration,
)


def clamp(value: float, low: float, high: float) -> float:
    return max(low, min(value, high))


def _mean(values: list[float], fallback: float = 0.0) -> float:
    return sum(values) / len(values) if values else fallback


def _median(values: list[float], fallback: float = 0.0) -> float:
    return statistics.median(values) if values else fallback


def _pace_from_cut_length(avg_cut_seconds: float) -> str:
    if avg_cut_seconds <= 3.5:
        return "very_fast"
    if avg_cut_seconds <= 6.0:
        return "fast"
    if avg_cut_seconds <= 10.0:
        return "balanced"
    return "slow"


def _target_window_for_pace(pace: str) -> tuple[float, float, float]:
    if pace == "very_fast":
        return 8.0, 16.0, 28.0
    if pace == "fast":
        return 12.0, 24.0, 38.0
    if pace == "slow":
        return 24.0, 46.0, 70.0
    return 18.0, 36.0, 52.0


def download_reference_url(url: str, output_dir: Path, index: int) -> Path:
    parsed = urlparse(url)
    if parsed.scheme not in {"http", "https"}:
        raise ValueError("only http/https reference URLs are allowed")

    output_dir.mkdir(parents=True, exist_ok=True)
    template = output_dir / f"url_reference_{index}.%(ext)s"
    command = [
        sys.executable,
        "-m",
        "yt_dlp",
        "--no-playlist",
        "-f",
        "bv*+ba/b",
        "--merge-output-format",
        "mp4",
        "-o",
        str(template),
        url,
    ]
    result = subprocess.run(
        command,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=None,
    )
    if result.returncode != 0:
        raise RuntimeError(
            "reference URL download failed. "
            "Check that yt-dlp can access the URL and that you have rights to use it. "
            f"{result.stderr.strip()}"
        )

    candidates = sorted(output_dir.glob(f"url_reference_{index}.*"))
    if not candidates:
        raise RuntimeError("reference URL did not produce a downloadable video file")
    return candidates[0]


def analyze_reference_video(
    video_path: Path,
    work_dir: Path,
    label: str,
    kind: str = "file",
    url: str | None = None,
) -> dict[str, Any]:
    duration = probe_duration(video_path)
    scene_points = detect_scene_changes(
        video_path,
        threshold=get_settings().scene_change_threshold,
    )
    cut_points = [0.0, *[point for point in scene_points if 0 < point < duration], duration]
    cut_lengths = [
        max(0.001, cut_points[index + 1] - cut_points[index])
        for index in range(len(cut_points) - 1)
    ]

    silence_ratio = 0.0
    try:
        audio_path = work_dir / f"{video_path.stem}.reference.wav"
        extract_audio(video_path, audio_path)
        silences = detect_silence(
            audio_path,
            noise_db=get_settings().silence_noise_db,
            min_duration=get_settings().silence_min_duration,
        )
        silence_seconds = sum(item.duration for item in silences)
        silence_ratio = clamp(silence_seconds / max(duration, 0.001), 0.0, 1.0)
    except Exception:
        silence_ratio = 0.0

    scene_rate = len(scene_points) / max(duration / 60.0, 0.001)
    return {
        "label": label,
        "kind": kind,
        "path": str(video_path),
        "url": url,
        "duration": round(duration, 3),
        "scene_count": len(scene_points),
        "scene_rate_per_minute": round(scene_rate, 3),
        "average_cut_seconds": round(_mean(cut_lengths, duration), 3),
        "median_cut_seconds": round(_median(cut_lengths, duration), 3),
        "silence_ratio": round(silence_ratio, 4),
        "speech_ratio": round(1.0 - silence_ratio, 4),
    }


def build_style_profile(
    *,
    style_id: str,
    name: str,
    sources: list[dict[str, Any]],
    created_at: str | None = None,
) -> dict[str, Any]:
    valid_sources = [source for source in sources if not source.get("error")]
    if not valid_sources:
        raise ValueError("at least one reference video must be analyzed successfully")

    avg_cut = _mean(
        [float(source.get("average_cut_seconds") or 0) for source in valid_sources],
        6.0,
    )
    median_cut = _median(
        [float(source.get("median_cut_seconds") or source.get("average_cut_seconds") or 0) for source in valid_sources],
        avg_cut,
    )
    scene_rate = _mean(
        [float(source.get("scene_rate_per_minute") or 0) for source in valid_sources],
        8.0,
    )
    silence_ratio = _mean(
        [float(source.get("silence_ratio") or 0) for source in valid_sources],
        0.2,
    )
    speech_ratio = _mean(
        [float(source.get("speech_ratio") or 0) for source in valid_sources],
        0.8,
    )

    pace = _pace_from_cut_length(avg_cut)
    target_min, target_ideal, target_max = _target_window_for_pace(pace)
    hook_window = clamp(avg_cut * 2.2, 8.0, 24.0)
    silence_aggressiveness = clamp(0.35 + speech_ratio * 0.4 + scene_rate / 80.0, 0.3, 0.95)
    visual_sensitivity = clamp(scene_rate / 28.0, 0.2, 0.95)
    prefer_shorts = avg_cut <= 4.5 and scene_rate >= 12.0

    return {
        "style_id": style_id,
        "name": name or "Reference Style",
        "status": "ready",
        "message": "레퍼런스 스타일 학습 완료",
        "progress": 100,
        "source_count": len(sources),
        "ready_source_count": len(valid_sources),
        "pace": pace,
        "average_cut_seconds": round(avg_cut, 3),
        "median_cut_seconds": round(median_cut, 3),
        "hook_window_seconds": round(hook_window, 3),
        "silence_aggressiveness": round(silence_aggressiveness, 3),
        "visual_change_sensitivity": round(visual_sensitivity, 3),
        "target_segment_seconds_min": target_min,
        "target_segment_seconds_ideal": target_ideal,
        "target_segment_seconds_max": target_max,
        "prefer_news_structure": True,
        "prefer_shorts_structure": prefer_shorts,
        "caption_density": "high" if speech_ratio >= 0.78 else "medium",
        "transition_style": "hard_cut" if avg_cut <= 8.0 else "paced_cut",
        "scoring_weights": {
            "style_duration": round(1.1 if pace in {"very_fast", "fast"} else 0.8, 2),
            "hook": round(1.4 if hook_window <= 14.0 else 1.0, 2),
            "information_density": round(1.2 if speech_ratio >= 0.75 else 0.9, 2),
            "news_structure": 1.15,
            "silence_penalty": round(silence_aggressiveness, 2),
            "visual_motion": round(visual_sensitivity, 2),
        },
        "sources": sources,
        "error": None,
        "created_at": created_at,
    }


def profile_summary(profile: dict[str, Any] | None) -> str:
    if not profile:
        return "default"
    return (
        f"{profile.get('pace', 'balanced')} pace, "
        f"avg cut {float(profile.get('average_cut_seconds') or 0):.1f}s, "
        f"hook {float(profile.get('hook_window_seconds') or 0):.1f}s"
    )
