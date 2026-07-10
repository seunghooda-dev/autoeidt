import json
import re
import shlex
import subprocess
import sys
import time
from array import array
from dataclasses import dataclass
from functools import lru_cache
from hashlib import sha1
from pathlib import Path
from threading import Lock
from typing import Any

from app.config import get_settings
from app.job_cancellation import (
    JobCancelledError,
    current_cancellable_job_id,
    raise_if_job_cancelled,
)

RENDER_FRAME_RATE = 30
RENDER_FRAME_RATE_LABEL = str(RENDER_FRAME_RATE)
TIMELINE_TIMECODE_MODE = "non_drop"
TIMELINE_TIMEBASE_LABEL = "30p NDF"
# All generated media must be independent of source drop-frame/timecode metadata.
TIMELINE_OUTPUT_METADATA_ARGS = [
    "-map_metadata",
    "-1",
    "-map_chapters",
    "-1",
    "-write_tmcd",
    "0",
]


class FFmpegError(RuntimeError):
    pass


@dataclass(frozen=True)
class SilenceRange:
    start: float
    end: float
    duration: float


def _run(command: list[str], timeout: int | None = None) -> subprocess.CompletedProcess[str]:
    if current_cancellable_job_id() is not None:
        return _run_cancellable(command, timeout)
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


def _run_cancellable(
    command: list[str],
    timeout: int | None,
) -> subprocess.CompletedProcess[str]:
    started_at = time.monotonic()
    process = subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    try:
        while True:
            try:
                stdout, stderr = process.communicate(timeout=0.25)
                break
            except subprocess.TimeoutExpired:
                try:
                    raise_if_job_cancelled()
                except JobCancelledError:
                    process.terminate()
                    try:
                        process.communicate(timeout=3)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.communicate()
                    raise
                if timeout is not None and time.monotonic() - started_at >= timeout:
                    process.kill()
                    stdout, stderr = process.communicate()
                    raise subprocess.TimeoutExpired(
                        command,
                        timeout,
                        output=stdout,
                        stderr=stderr,
                    )
        raise_if_job_cancelled()
        result = subprocess.CompletedProcess(
            command,
            process.returncode,
            stdout,
            stderr,
        )
        if result.returncode != 0:
            pretty = " ".join(shlex.quote(part) for part in command)
            raise FFmpegError(f"command failed: {pretty}\n{result.stderr}")
        return result
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()


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


def _safe_float(value: Any, default: float = 0.0) -> float:
    try:
        if value is None or value == "":
            return default
        return float(value)
    except (TypeError, ValueError):
        return default


def _safe_int(value: Any, default: int = 0) -> int:
    try:
        if value is None or value == "":
            return default
        return int(float(value))
    except (TypeError, ValueError):
        return default


def _rate_to_float(rate: str | None) -> float:
    if not rate or rate == "0/0":
        return 0.0
    try:
        if "/" in rate:
            numerator, denominator = rate.split("/", 1)
            denominator_value = float(denominator)
            if denominator_value == 0:
                return 0.0
            return float(numerator) / denominator_value
        return float(rate)
    except (TypeError, ValueError):
        return 0.0


def _stream_timecode(
    streams: list[dict[str, Any]],
    format_info: dict[str, Any],
) -> str | None:
    for source in [*streams, format_info]:
        tags = source.get("tags") if isinstance(source, dict) else None
        if not isinstance(tags, dict):
            continue
        timecode = tags.get("timecode") or tags.get("TIMECODE")
        if timecode:
            return str(timecode)
    return None


def _normalize_non_drop_timecode(timecode: str | None) -> str | None:
    if not timecode:
        return None
    value = str(timecode).strip()
    match = re.match(r"^(\d{1,3}):(\d{2}):(\d{2})([:;.])(\d{2})$", value)
    if not match:
        return value.replace(";", ":").replace(".", ":")

    hours = int(match.group(1))
    minutes = min(int(match.group(2)), 59)
    seconds = min(int(match.group(3)), 59)
    frames = min(int(match.group(5)), RENDER_FRAME_RATE - 1)
    return f"{hours:02d}:{minutes:02d}:{seconds:02d}:{frames:02d}"


def _is_drop_frame_timecode(timecode: str | None) -> bool:
    return bool(timecode and (";" in timecode or "." in timecode))


def _audio_stream_label(stream: dict[str, Any], index: int) -> str:
    codec = str(stream.get("codec_name") or "unknown")
    channels = _safe_int(stream.get("channels"))
    layout = str(stream.get("channel_layout") or "").strip()
    channel_label = layout or (f"{channels}ch" if channels else "unknown")
    return f"A{index} {codec} {channel_label}"


def _infer_mxf_operational_pattern(
    video_streams: list[dict[str, Any]],
    audio_streams: list[dict[str, Any]],
) -> str:
    if video_streams and audio_streams:
        return "OP1a-like single-file MXF"
    if len(video_streams) + len(audio_streams) <= 1:
        return "Possible OP-Atom/separate essence MXF"
    return "MXF operational pattern unknown"


def summarize_media_probe(video_path: Path, payload: dict[str, Any]) -> dict[str, Any]:
    format_info = payload.get("format") or {}
    streams = payload.get("streams") or []
    if not isinstance(streams, list):
        streams = []
    video_streams = [item for item in streams if item.get("codec_type") == "video"]
    audio_streams = [item for item in streams if item.get("codec_type") == "audio"]
    audio_channel_count = sum(
        max(1, _safe_int(stream.get("channels"), 1)) for stream in audio_streams
    )
    video = video_streams[0] if video_streams else {}

    format_name = str(format_info.get("format_name") or "")
    format_long_name = str(format_info.get("format_long_name") or "")
    suffix = video_path.suffix.lower()
    is_mxf = suffix == ".mxf" or "mxf" in format_name.lower()
    duration = _safe_float(format_info.get("duration"))
    if duration <= 0 and video:
        duration = _safe_float(video.get("duration"))
    frame_rate = _rate_to_float(
        str(video.get("avg_frame_rate") or video.get("r_frame_rate") or "")
    )
    source_timecode = _stream_timecode(streams, format_info)
    timeline_timecode = _normalize_non_drop_timecode(source_timecode)
    source_drop_frame = _is_drop_frame_timecode(source_timecode)
    audio_labels = [
        _audio_stream_label(stream, index)
        for index, stream in enumerate(audio_streams[:4], start=1)
    ]
    if len(audio_streams) > 4:
        audio_labels.append(f"+{len(audio_streams) - 4} more")

    warnings: list[str] = []
    if not video_streams:
        warnings.append("비디오 스트림을 찾지 못했습니다.")
    if is_mxf and not audio_streams:
        warnings.append(
            "오디오가 분리된 OP-Atom MXF일 수 있습니다. 관련 오디오 파일도 확인해 주세요."
        )
    elif not audio_streams:
        warnings.append("오디오 스트림이 없습니다.")
    if frame_rate <= 0:
        warnings.append("프레임레이트를 확인하지 못했습니다.")
    elif abs(frame_rate - 30.0) > 0.005:
        warnings.append(
            f"소스 프레임레이트가 {frame_rate:.3f}fps입니다. "
            "현재 타임라인은 30.00fps non-drop 기준입니다."
        )
    if source_drop_frame:
        warnings.append(
            "소스 drop-frame 타임코드는 제거하고 30p non-drop 표기로 변환해 작업합니다."
        )
    if is_mxf and audio_channel_count >= 8:
        warnings.append(
            "방송 MXF 다중 오디오 채널입니다. 필요한 채널 매핑 확인이 필요합니다."
        )
    if is_mxf:
        warnings.append("방송 원본 MXF입니다. 렌더 전 코덱/프록시 검사를 권장합니다.")

    return {
        "path": str(video_path),
        "filename": video_path.name,
        "container": format_name,
        "format_long_name": format_long_name,
        "duration": round(duration, 3),
        "bit_rate": _safe_int(format_info.get("bit_rate")),
        "video_codec": str(video.get("codec_name") or ""),
        "video_codec_long_name": str(video.get("codec_long_name") or ""),
        "pixel_format": str(video.get("pix_fmt") or ""),
        "width": _safe_int(video.get("width")),
        "height": _safe_int(video.get("height")),
        "frame_rate": round(frame_rate, 3),
        "source_frame_rate": round(frame_rate, 3),
        "source_timecode": source_timecode,
        "source_drop_frame": source_drop_frame,
        "timeline_frame_rate": float(RENDER_FRAME_RATE),
        "timeline_timecode_mode": TIMELINE_TIMECODE_MODE,
        "timeline_timebase": TIMELINE_TIMEBASE_LABEL,
        "timecode": timeline_timecode,
        "audio_stream_count": len(audio_streams),
        "audio_channel_count": audio_channel_count,
        "audio_summary": ", ".join(audio_labels),
        "is_mxf": is_mxf,
        "mxf_operational_pattern": (
            _infer_mxf_operational_pattern(video_streams, audio_streams)
            if is_mxf
            else ""
        ),
        "can_analyze": bool(video_streams and duration > 0),
        "warnings": warnings,
    }


def probe_media_info(video_path: Path) -> dict[str, Any]:
    resolved = video_path.resolve(strict=True)
    stat = resolved.stat()
    return dict(
        _probe_media_info_cached(
            str(resolved),
            stat.st_size,
            stat.st_mtime_ns,
        )
    )


@lru_cache(maxsize=64)
def _probe_media_info_cached(
    resolved_path: str,
    _size: int,
    _mtime_ns: int,
) -> dict[str, Any]:
    video_path = Path(resolved_path)
    result = _run(
        [
            "ffprobe",
            "-v",
            "error",
            "-show_format",
            "-show_streams",
            "-of",
            "json",
            str(video_path),
        ],
        timeout=60,
    )
    return summarize_media_probe(video_path, json.loads(result.stdout))


@lru_cache(maxsize=None)
def _preview_proxy_lock(cache_key: str) -> Any:
    return Lock()


def create_preview_proxy(
    video_path: Path,
    start_seconds: float = 0.0,
    duration_seconds: float | None = None,
) -> tuple[Path, bool, float, float]:
    settings = get_settings()
    resolved = video_path.resolve(strict=True)
    stat = resolved.stat()
    source_start = max(0.0, float(start_seconds or 0.0))
    requested_duration = (
        float(duration_seconds)
        if duration_seconds is not None and duration_seconds > 0
        else float(settings.preview_proxy_seconds)
    )
    proxy_seconds = max(8.0, min(requested_duration, 600.0))
    audio_stream_count = _audio_stream_count(resolved)
    audio_channel_counts = _audio_channel_counts(resolved, audio_stream_count)
    audio_layout_signature = "-".join(str(count) for count in audio_channel_counts)
    cache_identity = (
        f"preview-v7|fps-before-scale|program-audio-a1-a2-{audio_layout_signature}|"
        f"{source_start:.3f}|{proxy_seconds:.3f}|{resolved}|"
        f"{stat.st_size}|{stat.st_mtime_ns}"
    )
    cache_key = sha1(cache_identity.encode("utf-8")).hexdigest()
    preview_dir = settings.data_dir / "preview_proxies"
    preview_dir.mkdir(parents=True, exist_ok=True)
    output_path = preview_dir / f"{cache_key}.mp4"
    if output_path.exists() and output_path.stat().st_size > 0:
        return output_path, True, source_start, proxy_seconds

    with _preview_proxy_lock(cache_key):
        if output_path.exists() and output_path.stat().st_size > 0:
            return output_path, True, source_start, proxy_seconds

        temp_path = output_path.with_suffix(".tmp.mp4")
        if temp_path.exists():
            temp_path.unlink()
        audio_args = _preview_audio_output_args(audio_channel_counts)
        try:
            _run(
                [
                    "ffmpeg",
                    "-y",
                    "-ss",
                    f"{source_start:.3f}",
                    "-i",
                    str(resolved),
                    "-map",
                    "0:v:0",
                    *audio_args,
                    "-sn",
                    "-dn",
                    "-t",
                    f"{proxy_seconds:.3f}",
                    "-vf",
                    f"fps={RENDER_FRAME_RATE_LABEL},scale=-2:540,format=yuv420p",
                    "-r",
                    RENDER_FRAME_RATE_LABEL,
                    "-c:v",
                    "libx264",
                    "-preset",
                    "ultrafast",
                    "-crf",
                    "30",
                    "-c:a",
                    "aac",
                    "-b:a",
                    "96k",
                    "-ac",
                    "2",
                    *TIMELINE_OUTPUT_METADATA_ARGS,
                    "-movflags",
                    "+faststart",
                    str(temp_path),
                ],
                timeout=None,
            )
            temp_path.replace(output_path)
        finally:
            if temp_path.exists():
                temp_path.unlink()
        return output_path, False, source_start, proxy_seconds


def _preview_audio_output_args(audio_channel_counts: list[int]) -> list[str]:
    if not audio_channel_counts:
        return []

    left_stream, left_channel = _logical_audio_channel(audio_channel_counts, 1)
    right_stream, right_channel = _logical_audio_channel(
        audio_channel_counts,
        2 if sum(audio_channel_counts) >= 2 else 1,
    )
    if left_stream == right_stream:
        filter_complex = (
            f"[0:a:{left_stream}]aresample=48000,"
            f"pan=stereo|c0=c{left_channel}|c1=c{right_channel}[previewa]"
        )
    else:
        filter_complex = (
            f"[0:a:{left_stream}]aresample=48000,"
            f"pan=mono|c0=c{left_channel}[previewleft];"
            f"[0:a:{right_stream}]aresample=48000,"
            f"pan=mono|c0=c{right_channel}[previewright];"
            "[previewleft][previewright]amerge=inputs=2,"
            "aformat=channel_layouts=stereo[previewa]"
        )

    return ["-filter_complex", filter_complex, "-map", "[previewa]"]


def _analysis_audio_output_args(audio_channel_counts: list[int]) -> list[str]:
    if not audio_channel_counts:
        return []

    left_stream, left_channel = _logical_audio_channel(audio_channel_counts, 1)
    right_stream, right_channel = _logical_audio_channel(
        audio_channel_counts,
        2 if sum(audio_channel_counts) >= 2 else 1,
    )
    if left_stream == right_stream:
        if left_channel == right_channel:
            filter_complex = (
                f"[0:a:{left_stream}]aresample=16000,"
                f"pan=mono|c0=c{left_channel}[analysisa]"
            )
        else:
            filter_complex = (
                f"[0:a:{left_stream}]aresample=16000,"
                f"pan=mono|c0=0.5*c{left_channel}+0.5*c{right_channel}"
                "[analysisa]"
            )
    else:
        filter_complex = (
            f"[0:a:{left_stream}]aresample=16000,"
            f"pan=mono|c0=c{left_channel}[analysisleft];"
            f"[0:a:{right_stream}]aresample=16000,"
            f"pan=mono|c0=c{right_channel}[analysisright];"
            "[analysisleft][analysisright]amix=inputs=2:duration=longest:"
            "dropout_transition=0:normalize=1[analysisa]"
        )
    return ["-filter_complex", filter_complex, "-map", "[analysisa]"]


def extract_audio(video_path: Path, audio_path: Path) -> Path:
    audio_path.parent.mkdir(parents=True, exist_ok=True)
    audio_stream_count = _audio_stream_count(video_path)
    audio_channel_counts = _audio_channel_counts(video_path, audio_stream_count)
    audio_args = _analysis_audio_output_args(audio_channel_counts)
    _run(
        [
            "ffmpeg",
            "-y",
            "-i",
            str(video_path),
            *audio_args,
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
    result = _run(command)

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
        "-an",
        "-sn",
        "-dn",
        "-filter:v",
        f"fps=2,scale=320:-2,select='gt(scene,{threshold})',showinfo",
        "-f",
        "null",
        "-",
    ]
    try:
        result = _run(command)
    except FFmpegError:
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
    return render_highlights_reencoded(video_path, segments, output_path)


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


def _segment_audio_pan(segment: dict) -> float:
    return max(-1.0, min(float(segment.get("audio_pan", 0.0)), 1.0))


def _segment_audio_channel_1_enabled(segment: dict) -> bool:
    channel_1 = bool(segment.get("audio_channel_1_enabled", True))
    channel_2 = bool(segment.get("audio_channel_2_enabled", True))
    return channel_1 or not channel_2


def _segment_audio_channel_2_enabled(segment: dict) -> bool:
    return bool(segment.get("audio_channel_2_enabled", True))


def _segment_audio_source_channel(segment: dict, side: str) -> int:
    fallback = 1 if side == "left" else 2
    try:
        value = int(segment.get(f"audio_source_channel_{side}", fallback) or fallback)
    except (TypeError, ValueError):
        value = fallback
    return max(1, min(value, 64))


def _segment_video_enabled(segment: dict) -> bool:
    return bool(segment.get("video_enabled", True))


def _segment_audio_normalize(segment: dict) -> bool:
    return bool(segment.get("audio_normalize", False))


def _segment_audio_loudness_target(segment: dict) -> float:
    try:
        value = float(segment.get("audio_loudness_target", -14.0))
    except (TypeError, ValueError):
        value = -14.0
    return max(-24.0, min(value, -12.0))


def _segment_playback_speed(segment: dict) -> float:
    return max(0.25, min(float(segment.get("playback_speed", 1.0)), 4.0))


def _segment_output_duration(segment: dict) -> float:
    source_duration = max(0.0, float(segment["end"]) - float(segment["start"]))
    return source_duration / _segment_playback_speed(segment)


def _segment_audio_fade_in(segment: dict, output_duration: float) -> float:
    return max(0.0, min(float(segment.get("audio_fade_in", 0.0)), output_duration / 2))


def _segment_audio_fade_out(segment: dict, output_duration: float) -> float:
    return max(0.0, min(float(segment.get("audio_fade_out", 0.0)), output_duration / 2))


def _segment_video_fade_in(segment: dict, output_duration: float) -> float:
    return max(0.0, min(float(segment.get("video_fade_in", 0.0)), output_duration / 2))


def _segment_video_fade_out(segment: dict, output_duration: float) -> float:
    return max(0.0, min(float(segment.get("video_fade_out", 0.0)), output_duration / 2))


def _segment_color_brightness(segment: dict) -> float:
    return max(-0.3, min(float(segment.get("color_brightness", 0.0)), 0.3))


def _segment_color_contrast(segment: dict) -> float:
    return max(0.5, min(float(segment.get("color_contrast", 1.0)), 1.8))


def _segment_color_saturation(segment: dict) -> float:
    return max(0.0, min(float(segment.get("color_saturation", 1.0)), 2.0))


def _segment_focus_x(segment: dict) -> float:
    return max(0.0, min(float(segment.get("focus_x", 0.5)), 1.0))


def _segment_focus_y(segment: dict) -> float:
    return max(0.0, min(float(segment.get("focus_y", 0.42)), 1.0))


def _segment_focus_keyframes(
    segment: dict,
    axis: str,
    fallback: float,
) -> list[tuple[float, float]]:
    speed = _segment_playback_speed(segment)
    points: list[tuple[float, float]] = []
    for item in segment.get("focus_keyframes", []):
        if not isinstance(item, dict):
            continue
        try:
            seconds = max(0.0, float(item.get("time", 0.0))) / speed
            value = max(0.0, min(float(item.get(axis, fallback)), 1.0))
        except (TypeError, ValueError):
            continue
        points.append((seconds, value))
    points.sort(key=lambda item: item[0])
    return points[:48]


def _focus_track_expression(
    points: list[tuple[float, float]],
    fallback: float,
) -> str:
    if not points:
        return f"{fallback:.6f}"
    if len(points) == 1:
        return f"{points[0][1]:.6f}"

    expression = f"{points[-1][1]:.6f}"
    for index in range(len(points) - 2, -1, -1):
        left_time, left_value = points[index]
        right_time, right_value = points[index + 1]
        midpoint = (left_time + right_time) / 2.0
        transition_half = min(0.12, max(0.03, (right_time - left_time) / 6.0))
        transition_start = max(left_time, midpoint - transition_half)
        transition_end = min(right_time, midpoint + transition_half)
        transition_duration = max(0.001, transition_end - transition_start)
        transition = (
            f"{left_value:.6f}+({right_value - left_value:.6f})*"
            f"clip((t-{transition_start:.6f})/{transition_duration:.6f},0,1)"
        )
        expression = (
            f"if(lt(t,{transition_start:.6f}),{left_value:.6f},"
            f"if(lt(t,{transition_end:.6f}),{transition},{expression}))"
        )
    return expression


def _portrait_reframe_filters(segment: dict) -> list[str]:
    focus_x = _segment_focus_x(segment)
    focus_y = _segment_focus_y(segment)
    focus_x_expression = _focus_track_expression(
        _segment_focus_keyframes(segment, "x", focus_x),
        focus_x,
    )
    focus_y_expression = _focus_track_expression(
        _segment_focus_keyframes(segment, "y", focus_y),
        focus_y,
    )
    tracked_x = [
        value
        for _, value in _segment_focus_keyframes(segment, "x", focus_x)
    ] or [focus_x]
    extend_edges = min(tracked_x) < 0.18 or max(tracked_x) > 0.82
    if not extend_edges:
        crop_x = f"max(0,min(iw-ow,iw*({focus_x_expression})-ow/2))"
        crop_y = f"max(0,min(ih-oh,ih*({focus_y_expression})-oh*0.38))"
        return [
            "crop=w='min(iw,ih*9/16)':h='min(ih,iw*16/9)':"
            f"x='{crop_x}':y='{crop_y}'",
            "scale=1080:1920",
            "setsar=1",
        ]

    filters = ["scale=1080:1920:force_original_aspect_ratio=increase"]
    filters.extend(
        [
            "pad=iw+2160:ih:1080:0:color=black",
            "fillborders=left=1080:right=1080:mode=smear",
        ]
    )
    crop_x = (
        "max(0,min(iw-1080,"
        f"1080+(iw-2160)*({focus_x_expression})-540))"
    )
    # Keep the detected face near the upper third while preserving headroom.
    crop_y = f"max(0,min(ih-1920,ih*({focus_y_expression})-730))"
    filters.extend(
        [
        f"crop=1080:1920:x='{crop_x}':y='{crop_y}'",
        "setsar=1",
        ]
    )
    return filters


def _atempo_filters(speed: float) -> list[str]:
    factors: list[float] = []
    remaining = speed
    while remaining > 2.0:
        factors.append(2.0)
        remaining /= 2.0
    while remaining < 0.5:
        factors.append(0.5)
        remaining /= 0.5
    factors.append(remaining)
    return [f"atempo={factor:.6f}" for factor in factors]


def _segment_uses_default_audio(segment: dict) -> bool:
    if bool(segment.get("audio_muted", False)):
        return False
    if abs(_segment_audio_volume(segment) - 1.0) > 0.001:
        return False
    if abs(_segment_audio_pan(segment)) > 0.001:
        return False
    if not _segment_audio_channel_1_enabled(segment):
        return False
    if not _segment_audio_channel_2_enabled(segment):
        return False
    if _segment_audio_source_channel(segment, "left") != 1:
        return False
    if _segment_audio_source_channel(segment, "right") != 2:
        return False
    if _segment_audio_normalize(segment):
        return False
    if abs(_segment_playback_speed(segment) - 1.0) > 0.001:
        return False
    if segment.get("audio_fade_in", 0.0) or segment.get("audio_fade_out", 0.0):
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
        speed = _segment_playback_speed(segment)
        for caption in enabled:
            caption_start = float(caption["start"])
            caption_end = float(caption["end"])
            if caption_start >= segment_end or caption_end <= segment_start:
                continue
            start = cursor + (max(caption_start, segment_start) - segment_start) / speed
            end = cursor + (min(caption_end, segment_end) - segment_start) / speed
            text = str(caption.get("text") or "").strip()
            if text and end > start:
                entries.append((start, end, text))
        cursor += _segment_output_duration(segment)

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


def _caption_style_force_style(style: dict | None) -> str:
    style = style or {}
    font_name = re.sub(r"[^A-Za-z0-9 _.-]", "", str(style.get("font_name") or "Arial")) or "Arial"
    font_size = max(14, min(int(style.get("font_size") or 24), 72))
    primary_color = str(style.get("primary_color") or "&H00FFFFFF")
    outline_color = str(style.get("outline_color") or "&H90000000")
    if not re.fullmatch(r"&H[0-9A-Fa-f]{8}", primary_color):
        primary_color = "&H00FFFFFF"
    if not re.fullmatch(r"&H[0-9A-Fa-f]{8}", outline_color):
        outline_color = "&H90000000"
    outline = max(0, min(int(style.get("outline") or 2), 8))
    shadow = max(0, min(int(style.get("shadow") or 0), 8))
    alignment = max(1, min(int(style.get("alignment") or 2), 9))
    margin_v = max(0, min(int(style.get("margin_v") or 72), 360))
    return (
        f"FontName={font_name},FontSize={font_size},"
        f"PrimaryColour={primary_color},OutlineColour={outline_color},"
        f"BorderStyle=1,Outline={outline},Shadow={shadow},"
        f"Alignment={alignment},MarginV={margin_v}"
    )


@lru_cache(maxsize=64)
def _audio_channel_counts_cached(
    resolved_path: str,
    _size: int,
    _mtime_ns: int,
) -> tuple[int, ...] | None:
    try:
        result = _run(
            [
                "ffprobe",
                "-v",
                "error",
                "-select_streams",
                "a",
                "-show_entries",
                "stream=channels",
                "-of",
                "json",
                resolved_path,
            ],
            timeout=60,
        )
        data = json.loads(result.stdout or "{}")
        return tuple(
            max(1, _safe_int(stream.get("channels"), 1))
            for stream in data.get("streams") or []
            if isinstance(stream, dict)
        )
    except (FFmpegError, json.JSONDecodeError, OSError):
        return None


def _cached_audio_channel_counts(video_path: Path) -> tuple[int, ...] | None:
    try:
        resolved = video_path.resolve(strict=True)
        stat = resolved.stat()
    except OSError:
        return None
    return _audio_channel_counts_cached(
        str(resolved),
        stat.st_size,
        stat.st_mtime_ns,
    )


def _audio_stream_count(video_path: Path) -> int:
    counts = _cached_audio_channel_counts(video_path)
    return len(counts) if counts is not None else 1


def _audio_channel_counts(
    video_path: Path,
    fallback_stream_count: int,
) -> list[int]:
    counts = _cached_audio_channel_counts(video_path)
    if counts:
        return list(counts)
    return [1] * max(0, fallback_stream_count)


def _logical_audio_channel(
    channel_counts: list[int],
    requested_channel: int,
) -> tuple[int, int]:
    if not channel_counts:
        return 0, 0
    total = max(1, sum(channel_counts))
    remaining = max(1, min(requested_channel, total)) - 1
    for stream_index, channel_count in enumerate(channel_counts):
        if remaining < channel_count:
            return stream_index, remaining
        remaining -= channel_count
    return len(channel_counts) - 1, max(0, channel_counts[-1] - 1)


def _silence_audio_filter(label: str, duration: float, layout: str = "mono") -> str:
    return (
        f"anullsrc=channel_layout={layout}:sample_rate=48000,"
        f"atrim=duration={duration:.6f},asetpts=PTS-STARTPTS[{label}]"
    )


def _segment_audio_source_filters(
    index: int,
    audio_start: float,
    audio_end: float,
    video_duration: float,
    volume: float,
    channel_1_enabled: bool,
    channel_2_enabled: bool,
    audio_channel_counts: list[int],
    source_channel_left: int,
    source_channel_right: int,
) -> tuple[list[str], str]:
    filters: list[str] = []
    source_label = f"asrc{index}"
    if volume <= 0 or (not channel_1_enabled and not channel_2_enabled):
        filters.append(_silence_audio_filter(source_label, video_duration, "stereo"))
        return filters, f"[{source_label}]"

    if not audio_channel_counts:
        filters.append(_silence_audio_filter(source_label, video_duration, "stereo"))
        return filters, f"[{source_label}]"

    left_stream, left_channel = _logical_audio_channel(
        audio_channel_counts,
        source_channel_left,
    )
    right_stream, right_channel = _logical_audio_channel(
        audio_channel_counts,
        source_channel_right,
    )

    if left_stream != right_stream:
        channel_labels: list[str] = []
        for output_index, (stream_index, stream_channel, enabled) in enumerate(
            [
                (left_stream, left_channel, channel_1_enabled),
                (right_stream, right_channel, channel_2_enabled),
            ]
        ):
            channel_label = f"a{index}ch{output_index + 1}"
            if enabled:
                filters.append(
                    f"[0:a:{stream_index}]"
                    f"atrim=start={audio_start:.6f}:end={audio_end:.6f},"
                    "asetpts=PTS-STARTPTS,"
                    f"pan=mono|c0=c{stream_channel},"
                    f"volume={volume:.3f},"
                    "apad,"
                    f"atrim=duration={video_duration:.6f},"
                    f"asetpts=PTS-STARTPTS[{channel_label}]"
                )
            else:
                filters.append(
                    _silence_audio_filter(channel_label, video_duration, "mono")
                )
            channel_labels.append(f"[{channel_label}]")
        filters.append(
            f"{''.join(channel_labels)}amerge=inputs=2,"
            f"aformat=channel_layouts=stereo[{source_label}]"
        )
        return filters, f"[{source_label}]"

    left_expr = f"c{left_channel}" if channel_1_enabled else "0*c0"
    right_expr = f"c{right_channel}" if channel_2_enabled else "0*c0"
    filters.append(
        f"[0:a:{left_stream}]"
        f"atrim=start={audio_start:.6f}:end={audio_end:.6f},"
        "asetpts=PTS-STARTPTS,"
        f"volume={volume:.3f},"
        f"pan=stereo|c0={left_expr}|c1={right_expr},"
        "apad,"
        f"atrim=duration={video_duration:.6f},"
        f"asetpts=PTS-STARTPTS[{source_label}]"
    )
    return filters, f"[{source_label}]"


def _render_reencode_with_video_args(
    video_path: Path,
    segments: list[dict],
    output_path: Path,
    video_args: list[str],
    aspect_ratio: str = "16:9",
    captions: list[dict] | None = None,
    caption_style: dict | None = None,
) -> Path:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    filters: list[str] = []
    concat_inputs: list[str] = []
    audio_stream_count = _audio_stream_count(video_path)
    audio_channel_counts = _audio_channel_counts(video_path, audio_stream_count)
    source_starts = [float(segment["start"]) for segment in segments]
    source_starts.extend(_segment_audio_start(segment) for segment in segments)
    input_seek = max(0.0, min(source_starts, default=0.0) - 2.0)
    for index, segment in enumerate(segments):
        start = float(segment["start"]) - input_seek
        end = float(segment["end"]) - input_seek
        video_duration = max(0.000001, end - start)
        speed = _segment_playback_speed(segment)
        output_duration = max(0.000001, video_duration / speed)
        audio_start = _segment_audio_start(segment) - input_seek
        audio_end = _segment_audio_end(segment) - input_seek
        if audio_end <= audio_start:
            audio_start = start
            audio_end = end
        volume = (
            0.0
            if segment.get("audio_muted", False)
            else _segment_audio_volume(segment)
        )
        channel_1_enabled = _segment_audio_channel_1_enabled(segment)
        channel_2_enabled = _segment_audio_channel_2_enabled(segment)
        source_channel_left = _segment_audio_source_channel(segment, "left")
        source_channel_right = _segment_audio_source_channel(segment, "right")
        video_steps = [
            f"[0:v]trim=start={start:.6f}:end={end:.6f}",
            f"setpts=(PTS-STARTPTS)/{speed:.6f}",
        ]
        brightness = _segment_color_brightness(segment)
        contrast = _segment_color_contrast(segment)
        saturation = _segment_color_saturation(segment)
        if (
            abs(brightness) > 0.001
            or abs(contrast - 1.0) > 0.001
            or abs(saturation - 1.0) > 0.001
        ):
            video_steps.append(
                f"eq=brightness={brightness:.6f}:"
                f"contrast={contrast:.6f}:saturation={saturation:.6f}"
            )
        if not _segment_video_enabled(segment):
            video_steps.append("drawbox=x=0:y=0:w=iw:h=ih:color=black:t=fill")
        if aspect_ratio == "9:16":
            video_steps.extend(_portrait_reframe_filters(segment))
        video_steps.append("format=yuv420p")
        video_fade_in = _segment_video_fade_in(segment, output_duration)
        video_fade_out = _segment_video_fade_out(segment, output_duration)
        if video_fade_in > 0:
            video_steps.append(f"fade=t=in:st=0:d={video_fade_in:.6f}")
        if video_fade_out > 0:
            fade_start = max(0.0, output_duration - video_fade_out)
            video_steps.append(f"fade=t=out:st={fade_start:.6f}:d={video_fade_out:.6f}")
        video_steps[-1] = f"{video_steps[-1]}[v{index}]"
        filters.append(",".join(video_steps))
        audio_source_filters, audio_source = _segment_audio_source_filters(
            index,
            audio_start,
            audio_end,
            video_duration,
            volume,
            channel_1_enabled,
            channel_2_enabled,
            audio_channel_counts,
            source_channel_left,
            source_channel_right,
        )
        filters.extend(audio_source_filters)
        pan = _segment_audio_pan(segment)
        left_gain = 1.0 if pan <= 0 else 1.0 - pan
        right_gain = 1.0 if pan >= 0 else 1.0 + pan
        audio_steps = [
            f"{audio_source}asetpts=PTS-STARTPTS",
            (
                f"pan=stereo|c0={left_gain:.6f}*c0|c1={right_gain:.6f}*c1"
                if abs(pan) > 0.001
                else "anull"
            ),
            *_atempo_filters(speed),
            "apad",
            f"atrim=duration={output_duration:.6f}",
            "asetpts=PTS-STARTPTS",
        ]
        if _segment_audio_normalize(segment) and volume > 0:
            loudness_target = _segment_audio_loudness_target(segment)
            true_peak = -2.0 if loudness_target <= -20 else -1.5
            audio_steps.append(
                f"loudnorm=I={loudness_target:.1f}:TP={true_peak:.1f}:LRA=11"
            )
        fade_in = _segment_audio_fade_in(segment, output_duration)
        fade_out = _segment_audio_fade_out(segment, output_duration)
        if fade_in > 0:
            audio_steps.append(f"afade=t=in:st=0:d={fade_in:.6f}")
        if fade_out > 0:
            fade_start = max(0.0, output_duration - fade_out)
            audio_steps.append(f"afade=t=out:st={fade_start:.6f}:d={fade_out:.6f}")
        audio_steps[-1] = f"{audio_steps[-1]}[a{index}]"
        filters.append(
            ",".join(audio_steps)
        )
        concat_inputs.append(f"[v{index}][a{index}]")

    filter_complex = ";".join(filters)
    filter_complex += f";{''.join(concat_inputs)}concat=n={len(segments)}:v=1:a=1[basev][outa]"

    video_chain = "[basev]"
    if aspect_ratio == "9:16":
        filter_complex += ";[basev]setsar=1[framedv]"
        video_chain = "[framedv]"
    elif aspect_ratio == "1:1":
        filter_complex += (
            ";[basev]scale=1080:1080:force_original_aspect_ratio=decrease,"
            "pad=1080:1080:(ow-iw)/2:(oh-ih)/2,setsar=1[framedv]"
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
        force_style = _caption_style_force_style(caption_style)
        filter_complex += (
            f";{video_chain}fps={RENDER_FRAME_RATE_LABEL},"
            f"subtitles='{_subtitle_filter_path(caption_file)}':"
            f"force_style='{force_style}',format=yuv420p[outv]"
        )
    else:
        filter_complex += (
            f";{video_chain}fps={RENDER_FRAME_RATE_LABEL},format=yuv420p[outv]"
        )

    _run(
        [
            "ffmpeg",
            "-y",
            "-ss",
            f"{input_seek:.6f}",
            "-i",
            str(video_path),
            "-filter_complex",
            filter_complex,
            "-map",
            "[outv]",
            "-map",
            "[outa]",
            *video_args,
            "-r",
            RENDER_FRAME_RATE_LABEL,
            "-c:a",
            "aac",
            "-b:a",
            "192k",
            *TIMELINE_OUTPUT_METADATA_ARGS,
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
    caption_style: dict | None = None,
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
                caption_style=caption_style,
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
        caption_style=caption_style,
    )


def render_highlights(
    video_path: Path,
    segments: list[dict],
    output_path: Path,
    aspect_ratio: str = "16:9",
    captions: list[dict] | None = None,
    caption_style: dict | None = None,
) -> Path:
    normalized = sorted(
        segments,
        key=lambda item: int(item.get("order") or 0),
    )
    if not normalized:
        raise ValueError("at least one segment is required")

    return render_highlights_reencoded(
        video_path,
        normalized,
        output_path,
        aspect_ratio=aspect_ratio,
        captions=captions,
        caption_style=caption_style,
    )
