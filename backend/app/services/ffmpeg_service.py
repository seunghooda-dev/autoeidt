import json
import re
import shlex
import subprocess
import sys
from array import array
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


def generate_waveform(audio_path: Path, bucket_count: int = 900) -> list[float]:
    result = subprocess.run(
        [
            "ffmpeg",
            "-hide_banner",
            "-i",
            str(audio_path),
            "-f",
            "s16le",
            "-acodec",
            "pcm_s16le",
            "-ac",
            "1",
            "-ar",
            "8000",
            "-",
        ],
        capture_output=True,
    )
    if result.returncode != 0 or not result.stdout:
        return []

    samples = array("h")
    samples.frombytes(result.stdout)
    if sys.byteorder == "big":
        samples.byteswap()
    if not samples:
        return []

    bucket_count = max(64, min(bucket_count, len(samples)))
    bucket_size = max(1, len(samples) // bucket_count)
    peaks: list[float] = []
    for index in range(bucket_count):
        start = index * bucket_size
        end = len(samples) if index == bucket_count - 1 else min(len(samples), start + bucket_size)
        if start >= len(samples):
            peaks.append(0.0)
            continue
        peak = max(abs(value) for value in samples[start:end])
        peaks.append(round(min(1.0, peak / 32768.0), 3))
    return peaks


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


def _segment_audio_start(segment: dict) -> float:
    value = segment.get("audio_start")
    if value is None:
        value = segment["start"]
    return float(value)


def _segment_audio_end(segment: dict) -> float:
    value = segment.get("audio_end")
    if value is None:
        value = segment["end"]
    return float(value)


def _segment_audio_volume(segment: dict) -> float:
    return max(0.0, min(float(segment.get("audio_volume", 1.0)), 2.0))


def _segment_uses_default_audio(segment: dict) -> bool:
    if bool(segment.get("audio_muted", False)):
        return False
    if abs(_segment_audio_volume(segment) - 1.0) > 0.001:
        return False
    if not bool(segment.get("audio_linked", True)):
        return False
    return (
        abs(_segment_audio_start(segment) - float(segment["start"])) < 0.001
        and abs(_segment_audio_end(segment) - float(segment["end"])) < 0.001
    )


def _all_segments_use_default_audio(segments: list[dict]) -> bool:
    return all(_segment_uses_default_audio(segment) for segment in segments)


def _subtitle_filter_path(path: Path) -> str:
    normalized = str(path.resolve()).replace("\\", "/")
    normalized = normalized.replace(":", r"\:").replace("'", r"\'")
    return normalized


def _srt_time(seconds: float) -> str:
    milliseconds = int(round(seconds * 1000))
    hours = milliseconds // 3_600_000
    milliseconds %= 3_600_000
    minutes = milliseconds // 60_000
    milliseconds %= 60_000
    secs = milliseconds // 1000
    millis = milliseconds % 1000
    return f"{hours:02}:{minutes:02}:{secs:02},{millis:03}"


def _write_caption_srt(
    captions: list[dict],
    segments: list[dict],
    output_path: Path,
) -> Path | None:
    enabled = [caption for caption in captions if caption.get("enabled", True)]
    if not enabled:
        return None

    output_path.parent.mkdir(parents=True, exist_ok=True)
    entries: list[tuple[float, float, str]] = []
    cursor = 0.0
    for segment in segments:
        segment_start = float(segment["start"])
        segment_end = float(segment["end"])
        for caption in enabled:
            caption_start = float(caption["start"])
            caption_end = float(caption["end"])
            if caption_start >= segment_end or caption_end <= segment_start:
                continue
            start = cursor + max(caption_start, segment_start) - segment_start
            end = cursor + min(caption_end, segment_end) - segment_start
            text = str(caption.get("text") or "").strip()
            if text and end > start:
                entries.append((start, end, text))
        cursor += max(0.0, segment_end - segment_start)

    if not entries:
        return None

    lines: list[str] = []
    for index, (start, end, text) in enumerate(entries, start=1):
        lines.append(str(index))
        lines.append(f"{_srt_time(start)} --> {_srt_time(end)}")
        lines.append(text.replace("\n", " "))
        lines.append("")
    output_path.write_text("\n".join(lines), encoding="utf-8")
    return output_path


def _render_reencode_with_video_args(
    video_path: Path,
    segments: list[dict],
    output_path: Path,
    video_args: list[str],
    aspect_ratio: str = "16:9",
    captions: list[dict] | None = None,
) -> Path:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    filters: list[str] = []
    concat_inputs: list[str] = []
    for index, segment in enumerate(segments):
        start = float(segment["start"])
        end = float(segment["end"])
        video_duration = max(0.001, end - start)
        audio_start = _segment_audio_start(segment)
        audio_end = _segment_audio_end(segment)
        if audio_end <= audio_start:
            audio_start = start
            audio_end = end
        volume = 0.0 if segment.get("audio_muted", False) else _segment_audio_volume(segment)
        filters.append(
            f"[0:v]trim=start={start:.3f}:end={end:.3f},setpts=PTS-STARTPTS[v{index}]"
        )
        filters.append(
            f"[0:a]atrim=start={audio_start:.3f}:end={audio_end:.3f},"
            "asetpts=PTS-STARTPTS,"
            f"volume={volume:.3f},"
            "apad,"
            f"atrim=duration={video_duration:.3f},"
            f"asetpts=PTS-STARTPTS[a{index}]"
        )
        concat_inputs.append(f"[v{index}][a{index}]")

    filter_complex = ";".join(filters)
    filter_complex += f";{''.join(concat_inputs)}concat=n={len(segments)}:v=1:a=1[basev][outa]"

    video_chain = "[basev]"
    if aspect_ratio == "9:16":
        filter_complex += (
            ";[basev]scale=1080:1920:force_original_aspect_ratio=increase,"
            "crop=1080:1920,setsar=1[framedv]"
        )
        video_chain = "[framedv]"
    else:
        filter_complex += ";[basev]scale=1920:1080:force_original_aspect_ratio=decrease," \
            "pad=1920:1080:(ow-iw)/2:(oh-ih)/2,setsar=1[framedv]"
        video_chain = "[framedv]"

    caption_file = None
    if captions:
        caption_file = _write_caption_srt(
            captions,
            segments,
            output_path.with_suffix(".srt"),
        )
    if caption_file is not None:
        filter_complex += (
            f";{video_chain}subtitles='{_subtitle_filter_path(caption_file)}':"
            "force_style='FontName=Arial,FontSize=24,PrimaryColour=&H00FFFFFF,"
            "OutlineColour=&H90000000,BorderStyle=1,Outline=2,Shadow=0,"
            "Alignment=2,MarginV=72'[outv]"
        )
    else:
        filter_complex += f";{video_chain}format=yuv420p[outv]"

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
    return render_highlights_reencoded(video_path, segments, output_path)


def render_highlights_reencoded(
    video_path: Path,
    segments: list[dict],
    output_path: Path,
    aspect_ratio: str = "16:9",
    captions: list[dict] | None = None,
) -> Path:
    settings = get_settings()
    if settings.prefer_gpu_encoding and _encoder_available("h264_nvenc"):
        try:
            return _render_reencode_with_video_args(
                video_path,
                segments,
                output_path,
                ["-c:v", "h264_nvenc", "-preset", "p4", "-cq", "20"],
                aspect_ratio=aspect_ratio,
                captions=captions,
            )
        except FFmpegError:
            pass

    return _render_reencode_with_video_args(
        video_path,
        segments,
        output_path,
        ["-c:v", "libx264", "-preset", "veryfast", "-crf", "20"],
        aspect_ratio=aspect_ratio,
        captions=captions,
    )


def render_highlights(
    video_path: Path,
    segments: list[dict],
    output_path: Path,
    aspect_ratio: str = "16:9",
    captions: list[dict] | None = None,
) -> Path:
    normalized = sorted(
        segments,
        key=lambda item: int(item.get("order") or 0),
    )
    if not normalized:
        raise ValueError("at least one segment is required")

    if aspect_ratio == "16:9" and not captions and _all_segments_use_default_audio(normalized):
        try:
            return render_stream_copy(video_path, normalized, output_path)
        except Exception:
            pass

    fallback = output_path.with_name(f"{output_path.stem}_encoded{output_path.suffix}")
    return render_highlights_reencoded(
        video_path,
        normalized,
        fallback,
        aspect_ratio=aspect_ratio,
        captions=captions,
    )
