import json
import re
import shlex
import subprocess
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

from app.config import get_settings


class FFmpegError(RuntimeError):
    pass


@dataclass(frozen=True)
class SilenceRange:
    start: float
    end: float
    duration: float


def _run(command: list[str], timeout: int | None = None) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        command,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=timeout,
    )
    if result.returncode != 0:
        pretty = " ".join(shlex.quote(part) for part in command)
        raise FFmpegError(f"command failed: {pretty}\n{result.stderr}")
    return result


@lru_cache(maxsize=8)
def _encoder_available(name: str) -> bool:
    try:
        result = _run(["ffmpeg", "-hide_banner", "-encoders"], timeout=30)
    except Exception:
        return False
    return name in result.stdout


def probe_duration(video_path: Path) -> float:
    result = _run(
        [
            "ffprobe",
            "-v",
            "error",
            "-show_entries",
            "format=duration",
            "-of",
            "json",
            str(video_path),
        ],
        timeout=60,
    )
    payload = json.loads(result.stdout)
    return float(payload["format"]["duration"])


def extract_audio(video_path: Path, audio_path: Path) -> Path:
    audio_path.parent.mkdir(parents=True, exist_ok=True)
    _run(
        [
            "ffmpeg",
            "-y",
            "-i",
            str(video_path),
            "-vn",
            "-acodec",
            "pcm_s16le",
            "-ar",
            "16000",
            "-ac",
            "1",
            str(audio_path),
        ],
        timeout=None,
    )
    return audio_path


def detect_silence(
    audio_path: Path,
    noise_db: str = "-35dB",
    min_duration: float = 0.8,
) -> list[SilenceRange]:
    command = [
        "ffmpeg",
        "-hide_banner",
        "-i",
        str(audio_path),
        "-af",
        f"silencedetect=noise={noise_db}:d={min_duration}",
        "-f",
        "null",
        "-",
    ]
    result = subprocess.run(
        command,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    if result.returncode != 0:
        raise FFmpegError(result.stderr)

    ranges: list[SilenceRange] = []
    current_start: float | None = None
    for line in result.stderr.splitlines():
        start_match = re.search(r"silence_start:\s*([0-9.]+)", line)
        if start_match:
            current_start = float(start_match.group(1))
            continue

        end_match = re.search(
            r"silence_end:\s*([0-9.]+)\s*\|\s*silence_duration:\s*([0-9.]+)",
            line,
        )
        if end_match and current_start is not None:
            end = float(end_match.group(1))
            duration = float(end_match.group(2))
            ranges.append(SilenceRange(start=current_start, end=end, duration=duration))
            current_start = None

    return ranges


def detect_scene_changes(video_path: Path, threshold: float = 0.35) -> list[float]:
    command = [
        "ffmpeg",
        "-hide_banner",
        "-i",
        str(video_path),
        "-filter:v",
        f"select='gt(scene,{threshold})',showinfo",
        "-f",
        "null",
        "-",
    ]
    result = subprocess.run(
        command,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    if result.returncode != 0:
        return []

    points: list[float] = []
    for match in re.finditer(r"pts_time:([0-9.]+)", result.stderr):
        points.append(float(match.group(1)))
    return sorted(set(points))


def _ffconcat_path(path: Path) -> str:
    return str(path.resolve()).replace("\\", "/").replace("'", r"'\''")


def render_stream_copy(video_path: Path, segments: list[dict], output_path: Path) -> Path:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    concat_path = output_path.with_suffix(".ffconcat")
    lines = ["ffconcat version 1.0"]
    input_path = _ffconcat_path(video_path)
    for segment in segments:
        lines.append(f"file '{input_path}'")
        lines.append(f"inpoint {float(segment['start']):.3f}")
        lines.append(f"outpoint {float(segment['end']):.3f}")
    concat_path.write_text("\n".join(lines) + "\n", encoding="utf-8")

    _run(
        [
            "ffmpeg",
            "-y",
            "-f",
            "concat",
            "-safe",
            "0",
            "-i",
            str(concat_path),
            "-c",
            "copy",
            "-movflags",
            "+faststart",
            str(output_path),
        ],
        timeout=None,
    )
    return output_path


def _render_reencode_with_video_args(
    video_path: Path,
    segments: list[dict],
    output_path: Path,
    video_args: list[str],
) -> Path:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    filters: list[str] = []
    concat_inputs: list[str] = []
    for index, segment in enumerate(segments):
        start = float(segment["start"])
        end = float(segment["end"])
        filters.append(
            f"[0:v]trim=start={start:.3f}:end={end:.3f},setpts=PTS-STARTPTS[v{index}]"
        )
        filters.append(
            f"[0:a]atrim=start={start:.3f}:end={end:.3f},asetpts=PTS-STARTPTS[a{index}]"
        )
        concat_inputs.append(f"[v{index}][a{index}]")

    filter_complex = ";".join(filters)
    filter_complex += f";{''.join(concat_inputs)}concat=n={len(segments)}:v=1:a=1[outv][outa]"

    _run(
        [
            "ffmpeg",
            "-y",
            "-i",
            str(video_path),
            "-filter_complex",
            filter_complex,
            "-map",
            "[outv]",
            "-map",
            "[outa]",
            *video_args,
            "-c:a",
            "aac",
            "-b:a",
            "192k",
            "-movflags",
            "+faststart",
            str(output_path),
        ],
        timeout=None,
    )
    return output_path


def render_reencode(video_path: Path, segments: list[dict], output_path: Path) -> Path:
    settings = get_settings()
    if settings.prefer_gpu_encoding and _encoder_available("h264_nvenc"):
        try:
            return _render_reencode_with_video_args(
                video_path,
                segments,
                output_path,
                ["-c:v", "h264_nvenc", "-preset", "p4", "-cq", "20"],
            )
        except FFmpegError:
            pass

    return _render_reencode_with_video_args(
        video_path,
        segments,
        output_path,
        ["-c:v", "libx264", "-preset", "veryfast", "-crf", "20"],
    )


def render_highlights(video_path: Path, segments: list[dict], output_path: Path) -> Path:
    normalized = sorted(
        segments,
        key=lambda item: int(item.get("order") or 0),
    )
    if not normalized:
        raise ValueError("at least one segment is required")

    try:
        return render_stream_copy(video_path, normalized, output_path)
    except Exception:
        fallback = output_path.with_name(f"{output_path.stem}_encoded{output_path.suffix}")
        return render_reencode(video_path, normalized, fallback)
