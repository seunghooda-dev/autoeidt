import csv
import json
from pathlib import Path
from typing import Any

from app.celery_app import celery_app
from app.config import get_settings
from app.job_cancellation import (
    JobCancelledError,
    activate_job_cancellation,
    deactivate_job_cancellation,
    job_cancellation_requested,
    mark_job_cancelled,
    raise_if_job_cancelled,
)
from app.schemas import JobStatus
from app.services.ffmpeg_service import (
    detect_scene_changes,
    detect_silence,
    extract_audio,
    generate_waveform,
    probe_duration,
    render_highlights,
    sequence_output_duration_seconds,
)
from app.services.hybrid_cut import (
    build_protected_silences,
    overlaps,
    refine_highlights_with_hybrid_cut,
    silence_ranges_to_dicts,
)
from app.services.editing_skills import (
    align_highlights_to_transcript_boundaries,
    assign_highlight_topics,
    consolidate_overlapping_highlights,
)
from app.services.llm_service import analyze_highlights, fallback_review_highlights
from app.services.smart_reframe import analyze_highlight_framing
from app.services.reference_style import (
    analyze_reference_video,
    build_style_profile,
    download_reference_url,
)
from app.services.stt_service import transcribe_audio
from app.storage import now_iso, safe_filename, store

TIMECODE_FRAME_RATE = 30.0
TIMECODE_FRAME_DURATION = 1 / TIMECODE_FRAME_RATE


def _normalized_mp4_output_name(output_name: str | None, fallback: str) -> str:
    safe_name = safe_filename(output_name or fallback)
    path = Path(safe_name)
    stem = path.stem.strip("._") or Path(fallback).stem or "render"
    return f"{stem}.mp4"


def _unique_render_output_path(
    output_dir: Path,
    output_name: str | None,
    fallback: str,
    reserved_names: set[str] | None = None,
) -> Path:
    reserved_names = reserved_names if reserved_names is not None else set()
    base_name = _normalized_mp4_output_name(output_name, fallback)
    base_path = output_dir / base_name
    stem = base_path.stem
    suffix = base_path.suffix or ".mp4"

    for index in range(1, 10_000):
        name = base_name if index == 1 else f"{stem}_{index:03d}{suffix}"
        normalized = name.lower()
        candidate = output_dir / name
        if normalized not in reserved_names and not candidate.exists():
            reserved_names.add(normalized)
            return candidate

    raise RuntimeError("사용 가능한 렌더 출력 파일명을 만들 수 없습니다.")


def _render_output_duration_seconds(segments: list[dict[str, Any]]) -> float:
    return round(sequence_output_duration_seconds(segments), 3)


def _render_file_size_bytes(path: Path) -> int:
    try:
        return path.stat().st_size
    except OSError:
        return 0


def _render_output_warnings(
    duration_seconds: float,
    size_bytes: int,
) -> list[str]:
    warnings: list[str] = []
    if size_bytes <= 0:
        warnings.append("렌더 파일 크기가 0B입니다. 결과 파일을 다시 생성해 주세요.")
    elif size_bytes < 64 * 1024:
        warnings.append("렌더 파일 크기가 매우 작습니다. 재생 상태를 확인해 주세요.")
    if 0 < duration_seconds < 1:
        warnings.append("렌더 길이가 1초 미만입니다. 인/아웃 구간을 확인해 주세요.")
    return warnings


def _seconds_to_30p_timecode(seconds: float) -> str:
    frame_number = max(0, int(round(float(seconds) * TIMECODE_FRAME_RATE)))
    frames_per_second = int(TIMECODE_FRAME_RATE)
    frames = frame_number % frames_per_second
    total_seconds = frame_number // frames_per_second
    seconds_part = total_seconds % 60
    minutes = (total_seconds // 60) % 60
    hours = total_seconds // 3600
    return f"{hours:02d}:{minutes:02d}:{seconds_part:02d}:{frames:02d}"


def _write_batch_render_manifest(
    job_id: str,
    job: dict[str, Any],
    rendered_items: list[dict[str, Any]],
    options: dict[str, Any],
) -> list[dict[str, Any]]:
    output_dir = store.output_dir(job_id)
    json_path = output_dir / "render_manifest.json"
    csv_path = output_dir / "render_manifest.csv"
    generated_at = now_iso()
    total_duration = round(
        sum(float(item.get("duration_seconds") or 0) for item in rendered_items),
        3,
    )
    total_size = sum(int(item.get("size_bytes") or 0) for item in rendered_items)

    outputs: list[dict[str, Any]] = []
    for item_index, item in enumerate(rendered_items, start=1):
        aspect_ratio = str(
            item.get("aspect_ratio") or options.get("aspect_ratio") or "9:16"
        )
        outputs.append(
            {
                "index": item_index,
                "label": item.get("label") or f"Shorts {item_index:02}",
                "output_name": item.get("output_name") or "",
                "path": item.get("path") or "",
                "url": item.get("url") or "",
                "aspect_ratio": aspect_ratio,
                "duration_seconds": item.get("duration_seconds") or 0.0,
                "duration_timecode": _seconds_to_30p_timecode(
                    float(item.get("duration_seconds") or 0)
                ),
                "size_bytes": item.get("size_bytes") or 0,
                "warnings": item.get("warnings") or [],
                "segments": [
                    {
                        "order": segment.get("order", segment_index),
                        "start": segment.get("start", 0.0),
                        "end": segment.get("end", 0.0),
                        "source_in_timecode": _seconds_to_30p_timecode(
                            float(segment.get("start", 0.0) or 0.0)
                        ),
                        "source_out_timecode": _seconds_to_30p_timecode(
                            float(segment.get("end", 0.0) or 0.0)
                        ),
                        "audio_start": segment.get("audio_start"),
                        "audio_end": segment.get("audio_end"),
                        "audio_in_timecode": _seconds_to_30p_timecode(
                            float(
                                segment.get(
                                    "audio_start",
                                    segment.get("start", 0.0),
                                )
                                or 0.0
                            )
                        ),
                        "audio_out_timecode": _seconds_to_30p_timecode(
                            float(
                                segment.get("audio_end", segment.get("end", 0.0))
                                or 0.0
                            )
                        ),
                        "playback_speed": segment.get("playback_speed", 1.0),
                        "focus_x": segment.get("focus_x", 0.5),
                        "focus_y": segment.get("focus_y", 0.42),
                        "focus_confidence": segment.get("focus_confidence", 0.0),
                        "focus_keyframes": segment.get("focus_keyframes", []),
                        "topic_id": segment.get("topic_id", 0),
                        "reason": segment.get("reason", ""),
                        "script": segment.get("script", ""),
                        "tags": segment.get("tags", []),
                    }
                    for segment_index, segment in enumerate(
                        item.get("segments") or [],
                        start=1,
                    )
                    if isinstance(segment, dict)
                ],
            }
        )

    aspect_ratios = sorted(
        {
            str(
                item.get("aspect_ratio") or options.get("aspect_ratio") or "9:16"
            )
            for item in rendered_items
        }
    )
    manifest = {
        "job_id": job_id,
        "generated_at": generated_at,
        "original_filename": job.get("original_filename"),
        "source_video": job.get("video_path"),
        "timeline_frame_rate": TIMECODE_FRAME_RATE,
        "timeline_timecode_mode": "non_drop",
        "timeline_timebase": "30p NDF",
        "aspect_ratio": aspect_ratios[0] if len(aspect_ratios) == 1 else "mixed",
        "aspect_ratios": aspect_ratios,
        "include_captions": bool(options.get("include_captions", True)),
        "output_count": len(rendered_items),
        "total_duration_seconds": total_duration,
        "total_duration_timecode": _seconds_to_30p_timecode(total_duration),
        "total_size_bytes": total_size,
        "outputs": outputs,
    }
    json_path.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2, default=str),
        encoding="utf-8",
    )

    with csv_path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(
            [
                "item_index",
                "label",
                "output_name",
                "aspect_ratio",
                "path",
                "url",
                "duration_timecode",
                "duration_seconds",
                "size_bytes",
                "warning_count",
                "clip_order",
                "source_in_timecode",
                "source_out_timecode",
                "source_in_seconds",
                "source_out_seconds",
                "audio_in_timecode",
                "audio_out_timecode",
                "playback_speed",
                "reason",
                "script",
                "tags",
            ]
        )
        for output in outputs:
            segments = output["segments"] or [None]
            for segment in segments:
                writer.writerow(
                    [
                        output["index"],
                        output["label"],
                        output["output_name"],
                        output["aspect_ratio"],
                        output["path"],
                        output["url"],
                        output["duration_timecode"],
                        output["duration_seconds"],
                        output["size_bytes"],
                        len(output["warnings"]),
                        "" if segment is None else segment["order"],
                        "" if segment is None else segment["source_in_timecode"],
                        "" if segment is None else segment["source_out_timecode"],
                        "" if segment is None else segment["start"],
                        "" if segment is None else segment["end"],
                        "" if segment is None else segment["audio_in_timecode"],
                        "" if segment is None else segment["audio_out_timecode"],
                        "" if segment is None else segment["playback_speed"],
                        "" if segment is None else segment["reason"],
                        "" if segment is None else segment["script"],
                        ""
                        if segment is None
                        else "|".join(str(tag) for tag in segment["tags"]),
                    ]
                )

    return [
        {
            "label": "Render Manifest JSON",
            "path": str(json_path),
            "url": f"/api/jobs/{job_id}/download/{json_path.name}",
            "output_name": json_path.name,
            "kind": "manifest",
            "duration_seconds": 0.0,
            "size_bytes": _render_file_size_bytes(json_path),
            "warnings": [],
            "segments": [],
        },
        {
            "label": "Render Manifest CSV",
            "path": str(csv_path),
            "url": f"/api/jobs/{job_id}/download/{csv_path.name}",
            "output_name": csv_path.name,
            "kind": "manifest",
            "duration_seconds": 0.0,
            "size_bytes": _render_file_size_bytes(csv_path),
            "warnings": [],
            "segments": [],
        },
    ]


def _snap_to_timecode_frame(seconds: float) -> float:
    if seconds <= 0:
        return 0.0
    return round(seconds * TIMECODE_FRAME_RATE) / TIMECODE_FRAME_RATE


def _round_timecode_seconds(seconds: float) -> float:
    return round(_snap_to_timecode_frame(seconds), 6)


def _set_task_state(
    task: Any | None,
    job_id: str,
    status: JobStatus,
    stage: str,
    progress: int,
    message: str,
    **fields: Any,
) -> None:
    if status is not JobStatus.cancelled:
        raise_if_job_cancelled(job_id)
    payload = {
        "status": status.value,
        "stage": stage,
        "progress": progress,
        "message": message,
        **fields,
    }
    store.update(job_id, **payload)
    if task is not None:
        try:
            task.update_state(state=status.value.upper(), meta=payload)
        except Exception:
            pass


def _set_style_state(
    task: Any | None,
    style_id: str,
    status: str,
    progress: int,
    message: str,
    **fields: Any,
) -> None:
    payload = {
        "status": status,
        "progress": progress,
        "message": message,
        **fields,
    }
    store.update_style(style_id, **payload)
    if task is not None:
        try:
            task.update_state(state=status.upper(), meta=payload)
        except Exception:
            pass


def _normalize_highlights(
    highlights: list[dict[str, Any]],
    duration: float,
    preserve_order: bool = False,
) -> list[dict[str, Any]]:
    normalized: list[dict[str, Any]] = []
    for index, item in enumerate(highlights, start=1):
        start = _round_timecode_seconds(
            max(0.0, min(float(item["start"]), duration))
        )
        end = _round_timecode_seconds(
            max(0.0, min(float(item["end"]), duration))
        )
        if end <= start:
            end = _round_timecode_seconds(
                min(duration, start + TIMECODE_FRAME_DURATION)
            )
            if end <= start:
                continue
        audio_linked = bool(item.get("audio_linked", True))
        audio_start = item.get("audio_start")
        audio_end = item.get("audio_end")
        if audio_linked or audio_start is None or audio_end is None:
            normalized_audio_start = start
            normalized_audio_end = end
        else:
            normalized_audio_start = _round_timecode_seconds(
                max(0.0, min(float(audio_start), duration))
            )
            normalized_audio_end = _round_timecode_seconds(
                max(0.0, min(float(audio_end), duration))
            )
            if normalized_audio_end <= normalized_audio_start:
                normalized_audio_start = start
                normalized_audio_end = end
                audio_linked = True
        audio_volume = max(0.0, min(float(item.get("audio_volume", 1.0)), 2.0))
        audio_pan = max(-1.0, min(float(item.get("audio_pan", 0.0)), 1.0))
        audio_loudness_target = max(
            -24.0,
            min(float(item.get("audio_loudness_target", -14.0)), -12.0),
        )
        playback_speed = max(0.25, min(float(item.get("playback_speed", 1.0)), 4.0))
        transition_type = str(item.get("transition_type") or "cut").strip().lower()
        if transition_type not in {"cross_dissolve", "dip_black"}:
            transition_type = "cut"
        transition_duration = _round_timecode_seconds(
            max(
                0.0,
                min(float(item.get("transition_duration", 0.0)), 3.0),
            )
        )
        if transition_type == "cut":
            transition_duration = 0.0
        video_fade_in = max(0.0, min(float(item.get("video_fade_in", 0.0)), 10.0))
        video_fade_out = max(0.0, min(float(item.get("video_fade_out", 0.0)), 10.0))
        color_brightness = max(-0.3, min(float(item.get("color_brightness", 0.0)), 0.3))
        color_contrast = max(0.5, min(float(item.get("color_contrast", 1.0)), 1.8))
        color_saturation = max(0.0, min(float(item.get("color_saturation", 1.0)), 2.0))
        focus_x = max(0.0, min(float(item.get("focus_x", 0.5)), 1.0))
        focus_y = max(0.0, min(float(item.get("focus_y", 0.42)), 1.0))
        focus_confidence = max(
            0.0,
            min(float(item.get("focus_confidence", 0.0)), 1.0),
        )
        focus_keyframes: list[dict[str, float]] = []
        for keyframe in item.get("focus_keyframes", []):
            if not isinstance(keyframe, dict):
                continue
            try:
                focus_keyframes.append(
                    {
                        "time": round(
                            max(0.0, float(keyframe.get("time", 0.0))),
                            4,
                        ),
                        "x": round(
                            max(0.0, min(float(keyframe.get("x", focus_x)), 1.0)),
                            4,
                        ),
                        "y": round(
                            max(0.0, min(float(keyframe.get("y", focus_y)), 1.0)),
                            4,
                        ),
                    }
                )
            except (TypeError, ValueError):
                continue
        topic_id = max(0, int(item.get("topic_id", 0) or 0))
        audio_fade_in = max(0.0, min(float(item.get("audio_fade_in", 0.0)), 10.0))
        audio_fade_out = max(0.0, min(float(item.get("audio_fade_out", 0.0)), 10.0))
        audio_channel_1_enabled = bool(item.get("audio_channel_1_enabled", True))
        audio_channel_2_enabled = bool(item.get("audio_channel_2_enabled", True))
        audio_source_channel_left = max(
            1, min(int(item.get("audio_source_channel_left", 1) or 1), 64)
        )
        audio_source_channel_right = max(
            1, min(int(item.get("audio_source_channel_right", 2) or 2), 64)
        )
        if not audio_channel_1_enabled and not audio_channel_2_enabled:
            audio_channel_1_enabled = True
        score = max(0.0, min(float(item.get("score", 0.0)), 20.0))
        tags = [str(tag) for tag in item.get("tags", []) if str(tag).strip()]
        normalized.append(
            {
                "order": int(item.get("order") or index),
                "start": start,
                "end": end,
                "reason": str(item.get("reason", "AI 추천 구간")),
                "script": str(item.get("script", "")),
                "source": str(item.get("source", "ai")),
                "video_enabled": bool(item.get("video_enabled", True)),
                "video_fade_in": round(video_fade_in, 3),
                "video_fade_out": round(video_fade_out, 3),
                "color_brightness": round(color_brightness, 3),
                "color_contrast": round(color_contrast, 3),
                "color_saturation": round(color_saturation, 3),
                "focus_x": round(focus_x, 4),
                "focus_y": round(focus_y, 4),
                "focus_confidence": round(focus_confidence, 4),
                "focus_keyframes": focus_keyframes[:48],
                "topic_id": topic_id,
                "audio_start": normalized_audio_start,
                "audio_end": normalized_audio_end,
                "audio_muted": bool(item.get("audio_muted", False)),
                "audio_volume": round(audio_volume, 2),
                "audio_pan": round(audio_pan, 2),
                "audio_normalize": bool(item.get("audio_normalize", False)),
                "audio_loudness_target": round(audio_loudness_target, 1),
                "audio_linked": audio_linked,
                "audio_channel_1_enabled": audio_channel_1_enabled,
                "audio_channel_2_enabled": audio_channel_2_enabled,
                "audio_source_channel_left": audio_source_channel_left,
                "audio_source_channel_right": audio_source_channel_right,
                "playback_speed": round(playback_speed, 3),
                "transition_type": transition_type,
                "transition_duration": round(transition_duration, 6),
                "audio_fade_in": round(audio_fade_in, 3),
                "audio_fade_out": round(audio_fade_out, 3),
                "score": round(score, 2),
                "tags": tags[:8],
            }
        )
    normalized.sort(key=lambda item: item["order"] if preserve_order else item["start"])
    for index, item in enumerate(normalized, start=1):
        item["order"] = index
        if index == 1:
            item["transition_type"] = "cut"
            item["transition_duration"] = 0.0
            continue
        previous = normalized[index - 2]
        previous_duration = (
            float(previous["end"]) - float(previous["start"])
        ) / max(0.25, float(previous.get("playback_speed", 1.0)))
        incoming_duration = (
            float(item["end"]) - float(item["start"])
        ) / max(0.25, float(item.get("playback_speed", 1.0)))
        item["transition_duration"] = round(
            min(
                float(item.get("transition_duration", 0.0)),
                previous_duration / 2,
                incoming_duration / 2,
            ),
            6,
        )
    return normalized


def _captions_from_transcript(transcript: list[dict[str, Any]]) -> list[dict[str, Any]]:
    if transcript and all(item.get("source") == "fallback_stt" for item in transcript):
        return []

    captions: list[dict[str, Any]] = []
    for index, item in enumerate(transcript, start=1):
        text = str(item.get("text") or "").strip()
        if not text:
            continue
        captions.append(
            {
                "order": index,
                "start": round(float(item.get("start") or 0), 1),
                "end": round(float(item.get("end") or 0), 1),
                "text": text,
                "enabled": True,
            }
        )
    return captions


def _silences_overlapping_highlights(
    silences: list,
    highlights: list[dict[str, Any]],
) -> list:
    output = []
    for silence in silences:
        if any(
            overlaps(
                silence.start,
                silence.end,
                float(highlight["start"]),
                float(highlight["end"]),
            )
            for highlight in highlights
        ):
            output.append(silence)
    return output


def _generate_waveform_for_analysis(
    audio_path: Path,
    analysis_warnings: list[str],
) -> list[float]:
    try:
        return generate_waveform(audio_path)
    except Exception as exc:
        analysis_warnings.append(
            "오디오 파형 생성에 실패했지만 분석은 계속 진행합니다. "
            f"원인: {exc}"
        )
        return []


def _detect_silences_for_analysis(
    audio_path: Path,
    noise_db: str,
    min_duration: float,
    analysis_warnings: list[str],
) -> list:
    try:
        return detect_silence(
            audio_path,
            noise_db=noise_db,
            min_duration=min_duration,
        )
    except Exception as exc:
        analysis_warnings.append(
            "침묵 구간 탐지에 실패해 무음 컷 보정 없이 분석을 계속 진행합니다. "
            f"원인: {exc}"
        )
        return []


def _detect_scene_points_for_analysis(
    video_path: Path,
    threshold: float,
    analysis_warnings: list[str],
) -> list[float]:
    try:
        return detect_scene_changes(video_path, threshold=threshold)
    except Exception as exc:
        analysis_warnings.append(
            "화면 전환 탐지에 실패해 오디오/STT 기반 분석으로 계속 진행합니다. "
            f"원인: {exc}"
        )
        return []


def _build_protected_silences_for_analysis(
    video_path: Path,
    candidate_silences: list,
    scene_points: list[float],
    analysis_warnings: list[str],
) -> list:
    try:
        return build_protected_silences(
            video_path,
            candidate_silences,
            scene_points=scene_points,
        )
    except Exception as exc:
        analysis_warnings.append(
            "시각적 모션 보호 검사에 실패해 무음 컷 보호를 최소화했습니다. "
            f"원인: {exc}"
        )
        return [
            silence
            for silence in candidate_silences
            if any(
                silence.start <= point <= silence.end
                for point in scene_points
            )
        ]


def _analyze_framing_for_analysis(
    video_path: Path,
    highlights: list[dict[str, Any]],
    analysis_warnings: list[str],
) -> list[dict[str, Any]]:
    try:
        return analyze_highlight_framing(video_path, highlights)
    except Exception as exc:
        analysis_warnings.append(
            "화자 중심 구도 분석에 실패해 중앙 구도로 렌더링합니다. "
            f"원인: {exc}"
        )
        return [
            {
                **highlight,
                "focus_x": float(highlight.get("focus_x", 0.5)),
                "focus_y": float(highlight.get("focus_y", 0.42)),
                "focus_confidence": 0.0,
                "focus_keyframes": [],
            }
            for highlight in highlights
        ]


def analyze_video_job(job_id: str, task: Any | None = None) -> dict[str, Any]:
    settings = get_settings()
    cancellation_token = activate_job_cancellation(job_id)
    audio_path: Path | None = None
    try:
        job = store.load(job_id)
        video_path = Path(job["video_path"])
        work_dir = store.work_dir(job_id)
        audio_path = work_dir / "audio.wav"
        style_profile = job.get("style_profile")

        _set_task_state(
            task,
            job_id,
            JobStatus.processing,
            "probing",
            10,
            "영상 메타데이터 확인 중",
        )
        duration = probe_duration(video_path)

        _set_task_state(
            task,
            job_id,
            JobStatus.processing,
            "extracting_audio",
            25,
            "오디오 추출 중",
            duration=duration,
        )
        extract_audio(video_path, audio_path)

        _set_task_state(
            task,
            job_id,
            JobStatus.processing,
            "transcribing",
            45,
            "스크립트 추출 중",
            audio_path=str(audio_path),
        )
        transcript = transcribe_audio(audio_path, duration)
        analysis_warnings: list[str] = []
        if transcript and all(
            item.get("source") == "fallback_stt" for item in transcript
        ):
            fallback_reason = str(transcript[0].get("fallback_reason") or "")
            if fallback_reason.startswith("local_whisper_failed:"):
                message = (
                    "무료 로컬 Whisper 음성 인식이 실패하여 실제 대화 내용 분석 대신 "
                    "검토용 후보를 생성했습니다. 첫 실행 모델 다운로드, GPU/CPU 메모리, "
                    "또는 오디오 코덱 문제를 확인해 주세요."
                )
            elif fallback_reason == "openai_key_missing_and_local_whisper_disabled":
                message = (
                    "OPENAI_API_KEY가 없고 무료 로컬 Whisper가 비활성화되어 "
                    "실제 STT/LLM 내용 분석 대신 검토용 후보만 생성했습니다."
                )
            elif fallback_reason == "local_whisper_empty_transcript":
                message = (
                    "무료 로컬 Whisper가 실행됐지만 인식 가능한 음성을 찾지 못해 "
                    "실제 대화 내용 분석 대신 검토용 후보를 생성했습니다."
                )
            else:
                message = (
                    "음성 인식 엔진을 사용할 수 없어 실제 STT/LLM 내용 분석 대신 "
                    "검토용 후보만 생성했습니다."
                )
            analysis_warnings.append(
                message
            )
        captions = _captions_from_transcript(transcript)
        waveform = _generate_waveform_for_analysis(audio_path, analysis_warnings)

        _set_task_state(
            task,
            job_id,
            JobStatus.processing,
            "detecting_silence",
            62,
            "침묵 구간 탐지 중",
            transcript=transcript,
            captions=captions,
            waveform=waveform,
            analysis_warnings=analysis_warnings,
        )
        silence_aggressiveness = 0.6
        if isinstance(style_profile, dict):
            try:
                silence_aggressiveness = float(
                    style_profile.get("silence_aggressiveness", silence_aggressiveness)
                )
            except (TypeError, ValueError):
                silence_aggressiveness = 0.6
        min_silence = max(
            0.25,
            settings.silence_min_duration * (1.25 - min(silence_aggressiveness, 0.95)),
        )
        silence_ranges = _detect_silences_for_analysis(
            audio_path,
            settings.silence_noise_db,
            min_silence,
            analysis_warnings,
        )

        _set_task_state(
            task,
            job_id,
            JobStatus.processing,
            "checking_visual_changes",
            74,
            "장면 변화 분석 중",
            silences=silence_ranges_to_dicts(silence_ranges),
        )
        scene_points = _detect_scene_points_for_analysis(
            video_path,
            settings.scene_change_threshold,
            analysis_warnings,
        )

        _set_task_state(
            task,
            job_id,
            JobStatus.processing,
            "analyzing_highlights",
            84,
            "음성·화면·문맥 종합 분석 중",
            scene_count=len(scene_points),
        )
        raw_highlights = _normalize_highlights(
            analyze_highlights(
                transcript,
                duration,
                style_profile,
                silence_ranges=silence_ranges,
                scene_points=scene_points,
            ),
            duration,
        )
        if transcript and all(
            item.get("source") == "fallback_stt" for item in transcript
        ):
            raw_highlights = _normalize_highlights(
                fallback_review_highlights(
                    duration,
                    settings.target_highlight_seconds_min,
                    settings.target_highlight_seconds_max,
                    silence_ranges=silence_ranges,
                    scene_points=scene_points,
                ),
                duration,
            )
        candidate_silences = _silences_overlapping_highlights(
            silence_ranges,
            raw_highlights,
        )

        protected_silences = _build_protected_silences_for_analysis(
            video_path,
            candidate_silences,
            scene_points,
            analysis_warnings,
        )

        refined = refine_highlights_with_hybrid_cut(
            raw_highlights,
            candidate_silences,
            protected_silences,
            transcript,
        )
        if not refined:
            refined = raw_highlights
        refined = align_highlights_to_transcript_boundaries(refined, transcript)
        refined = consolidate_overlapping_highlights(refined)
        refined = assign_highlight_topics(refined)
        refined = _normalize_highlights(refined, duration)

        _set_task_state(
            task,
            job_id,
            JobStatus.processing,
            "tracking_speakers",
            94,
            "화자 중심 세로 구도 분석 중",
        )
        refined = _analyze_framing_for_analysis(
            video_path,
            refined,
            analysis_warnings,
        )
        refined = _normalize_highlights(refined, duration)

        _set_task_state(
            task,
            job_id,
            JobStatus.completed,
            "completed",
            100,
            "가편집 타임라인 생성 완료",
            duration=duration,
            transcript=transcript,
            captions=captions,
            waveform=waveform,
            segments=refined,
            protected_silences=silence_ranges_to_dicts(protected_silences),
            style_profile=style_profile,
            analysis_warnings=analysis_warnings,
        )
        return store.load(job_id)
    except JobCancelledError:
        if audio_path is not None:
            try:
                if audio_path.exists():
                    audio_path.unlink()
            except OSError:
                pass
        mark_job_cancelled(job_id, message="분석 작업이 취소되었습니다")
        return store.load(job_id)
    except Exception as exc:
        if job_cancellation_requested(job_id):
            if audio_path is not None:
                try:
                    if audio_path.exists():
                        audio_path.unlink()
                except OSError:
                    pass
            mark_job_cancelled(job_id, message="분석 작업이 취소되었습니다")
            return store.load(job_id)
        store.update(
            job_id,
            status=JobStatus.failed.value,
            stage="failed",
            progress=100,
            message="분석 작업 실패",
            error=str(exc),
        )
        raise
    finally:
        deactivate_job_cancellation(cancellation_token)


@celery_app.task(bind=True, name="app.tasks.analyze_video")
def analyze_video_task(self: Any, job_id: str) -> dict[str, Any]:
    return analyze_video_job(job_id, self)


def train_style_profile_job(style_id: str, task: Any | None = None) -> dict[str, Any]:
    try:
        style = store.load_style(style_id)
        inputs = style.get("reference_inputs") or []
        if not inputs:
            raise ValueError("레퍼런스 파일 또는 URL이 필요합니다.")

        _set_style_state(
            task,
            style_id,
            "processing",
            5,
            "레퍼런스 입력 확인 중",
        )
        reference_dir = store.style_upload_dir(style_id)
        work_dir = store.style_work_dir(style_id)
        sources: list[dict[str, Any]] = []
        total = max(len(inputs), 1)
        for index, item in enumerate(inputs, start=1):
            label = str(item.get("label") or f"Reference {index}")
            kind = str(item.get("kind") or "file")
            progress_base = 10 + int((index - 1) / total * 80)
            try:
                _set_style_state(
                    task,
                    style_id,
                    "processing",
                    progress_base,
                    f"레퍼런스 분석 중: {label}",
                    sources=sources,
                )
                if kind == "url":
                    url = str(item.get("url") or "")
                    video_path = download_reference_url(url, reference_dir, index)
                else:
                    video_path = Path(str(item.get("path") or ""))
                    url = item.get("url")
                metrics = analyze_reference_video(
                    video_path,
                    work_dir,
                    label=label,
                    kind=kind,
                    url=str(url) if url else None,
                )
                sources.append(metrics)
            except Exception as exc:
                sources.append(
                    {
                        "label": label,
                        "kind": kind,
                        "path": str(item.get("path") or ""),
                        "url": item.get("url"),
                        "error": str(exc),
                    }
                )

        profile = build_style_profile(
            style_id=style_id,
            name=str(style.get("name") or "Reference Style"),
            sources=sources,
            created_at=style.get("created_at") or now_iso(),
        )
        profile["reference_inputs"] = inputs
        store.save_style(style_id, profile)
        return store.load_style(style_id)
    except Exception as exc:
        store.update_style(
            style_id,
            status="failed",
            progress=100,
            message="레퍼런스 스타일 학습 실패",
            error=str(exc),
        )
        raise


@celery_app.task(bind=True, name="app.tasks.train_style_profile")
def train_style_profile_task(self: Any, style_id: str) -> dict[str, Any]:
    return train_style_profile_job(style_id, self)


def render_video_job(
    job_id: str,
    segments: list[dict[str, Any]],
    options: dict[str, Any] | None = None,
    task: Any | None = None,
) -> dict[str, Any]:
    cancellation_token = activate_job_cancellation(job_id)
    output_path: Path | None = None
    try:
        options = options or {}
        job = store.load(job_id)
        duration = float(job.get("duration") or 0)
        normalized = _normalize_highlights(
            segments,
            duration or 1_000_000.0,
            preserve_order=True,
        )
        if not normalized:
            raise ValueError("렌더링할 하이라이트 구간이 없습니다.")

        _set_task_state(
            task,
            job_id,
            JobStatus.rendering,
            "rendering",
            20,
            "최종 영상 렌더링 중",
            segments=normalized,
        )

        video_path = Path(job["video_path"])
        output_path = _unique_render_output_path(
            store.output_dir(job_id),
            str(options.get("output_name") or ""),
            "youtube_highlights.mp4",
        )
        captions = options.get("captions") or []
        if not options.get("include_captions", False):
            captions = []
        caption_style = options.get("caption_style") or {}
        rendered_path = render_highlights(
            video_path,
            normalized,
            output_path,
            aspect_ratio=str(options.get("aspect_ratio") or "16:9"),
            captions=captions,
            caption_style=caption_style,
        )
        render_duration_seconds = _render_output_duration_seconds(normalized)
        render_size_bytes = _render_file_size_bytes(rendered_path)
        render_warnings = _render_output_warnings(
            render_duration_seconds,
            render_size_bytes,
        )

        _set_task_state(
            task,
            job_id,
            JobStatus.rendered,
            "rendered",
            100,
            "최종 영상 렌더링 완료",
            render_path=str(rendered_path),
            render_url=f"/api/jobs/{job_id}/download",
            render_duration_seconds=render_duration_seconds,
            render_size_bytes=render_size_bytes,
            render_warnings=render_warnings,
        )
        return store.load(job_id)
    except JobCancelledError:
        if output_path is not None:
            try:
                if output_path.exists():
                    output_path.unlink()
            except OSError:
                pass
        mark_job_cancelled(job_id, message="렌더링 작업이 취소되었습니다")
        return store.load(job_id)
    except Exception as exc:
        if job_cancellation_requested(job_id):
            if output_path is not None:
                try:
                    if output_path.exists():
                        output_path.unlink()
                except OSError:
                    pass
            mark_job_cancelled(job_id, message="렌더링 작업이 취소되었습니다")
            return store.load(job_id)
        store.update(
            job_id,
            status=JobStatus.failed.value,
            stage="render_failed",
            progress=100,
            message="렌더링 작업 실패",
            error=str(exc),
        )
        raise
    finally:
        deactivate_job_cancellation(cancellation_token)


def render_batch_video_job(
    job_id: str,
    items: list[dict[str, Any]],
    options: dict[str, Any] | None = None,
    task: Any | None = None,
) -> dict[str, Any]:
    cancellation_token = activate_job_cancellation(job_id)
    output_path: Path | None = None
    rendered_items: list[dict[str, Any]] = []
    try:
        options = options or {}
        job = store.load(job_id)
        duration = float(job.get("duration") or 0)
        video_path = Path(job["video_path"])
        captions = options.get("captions") or []
        if not options.get("include_captions", True):
            captions = []
        caption_style = options.get("caption_style") or {}
        reserved_output_names: set[str] = set()
        total = max(len(items), 1)
        for index, item in enumerate(items, start=1):
            normalized = _normalize_highlights(
                list(item.get("segments") or []),
                duration or 1_000_000.0,
                preserve_order=True,
            )
            if not normalized:
                continue
            output_path = _unique_render_output_path(
                store.output_dir(job_id),
                str(item.get("output_name") or ""),
                f"shorts_{index:02}.mp4",
                reserved_output_names,
            )
            progress = 10 + int(index / total * 80)
            item_label = str(item.get("label") or f"Output {index}")
            _set_task_state(
                task,
                job_id,
                JobStatus.rendering,
                "batch_rendering",
                progress,
                f"{item_label} {index}/{total} 렌더링 중",
                batch_render_items=rendered_items,
            )
            aspect_ratio = str(
                item.get("aspect_ratio") or options.get("aspect_ratio") or "9:16"
            )
            rendered_path = render_highlights(
                video_path,
                normalized,
                output_path,
                aspect_ratio=aspect_ratio,
                captions=captions,
                caption_style=caption_style,
            )
            render_duration_seconds = _render_output_duration_seconds(normalized)
            render_size_bytes = _render_file_size_bytes(rendered_path)
            render_warnings = _render_output_warnings(
                render_duration_seconds,
                render_size_bytes,
            )
            rendered_items.append(
                {
                    "label": str(item.get("label") or f"Shorts {index:02}"),
                    "path": str(rendered_path),
                    "url": f"/api/jobs/{job_id}/download/{rendered_path.name}",
                    "output_name": rendered_path.name,
                    "kind": "video",
                    "aspect_ratio": aspect_ratio,
                    "duration_seconds": render_duration_seconds,
                    "size_bytes": render_size_bytes,
                    "warnings": render_warnings,
                    "segments": normalized,
                }
            )
        if not rendered_items:
            raise ValueError("렌더링할 쇼츠 후보가 없습니다.")

        manifest_items = _write_batch_render_manifest(
            job_id,
            job,
            rendered_items,
            options,
        )
        _set_task_state(
            task,
            job_id,
            JobStatus.rendered,
            "batch_rendered",
            100,
            "쇼츠 일괄 렌더링 완료",
            batch_render_items=rendered_items,
            render_manifest_items=manifest_items,
            render_path=rendered_items[0]["path"],
            render_url=rendered_items[0]["url"],
            render_duration_seconds=rendered_items[0]["duration_seconds"],
            render_size_bytes=rendered_items[0]["size_bytes"],
            render_warnings=[
                f"{item['label']}: {warning}"
                for item in rendered_items
                for warning in item.get("warnings", [])
            ],
        )
        return store.load(job_id)
    except JobCancelledError:
        if output_path is not None:
            try:
                if output_path.exists() and not any(
                    item.get("path") == str(output_path) for item in rendered_items
                ):
                    output_path.unlink()
            except OSError:
                pass
        mark_job_cancelled(
            job_id,
            message="쇼츠 일괄 렌더링이 취소되었습니다",
            batch_render_items=rendered_items,
        )
        return store.load(job_id)
    except Exception as exc:
        if job_cancellation_requested(job_id):
            if output_path is not None:
                try:
                    if output_path.exists() and not any(
                        item.get("path") == str(output_path)
                        for item in rendered_items
                    ):
                        output_path.unlink()
                except OSError:
                    pass
            mark_job_cancelled(
                job_id,
                message="쇼츠 일괄 렌더링이 취소되었습니다",
                batch_render_items=rendered_items,
            )
            return store.load(job_id)
        store.update(
            job_id,
            status=JobStatus.failed.value,
            stage="batch_render_failed",
            progress=100,
            message="쇼츠 일괄 렌더링 실패",
            error=str(exc),
        )
        raise
    finally:
        deactivate_job_cancellation(cancellation_token)


@celery_app.task(bind=True, name="app.tasks.render_video")
def render_video_task(
    self: Any,
    job_id: str,
    segments: list[dict[str, Any]],
    options: dict[str, Any] | None = None,
) -> dict[str, Any]:
    return render_video_job(job_id, segments, options, self)


@celery_app.task(bind=True, name="app.tasks.render_batch_video")
def render_batch_video_task(
    self: Any,
    job_id: str,
    items: list[dict[str, Any]],
    options: dict[str, Any] | None = None,
) -> dict[str, Any]:
    return render_batch_video_job(job_id, items, options, self)
