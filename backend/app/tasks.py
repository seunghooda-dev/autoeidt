from pathlib import Path
from typing import Any

from app.celery_app import celery_app
from app.config import get_settings
from app.schemas import JobStatus
from app.services.ffmpeg_service import (
    detect_silence,
    extract_audio,
    generate_waveform,
    probe_duration,
    render_highlights,
)
from app.services.hybrid_cut import (
    build_protected_silences,
    overlaps,
    refine_highlights_with_hybrid_cut,
    silence_ranges_to_dicts,
)
from app.services.llm_service import analyze_highlights
from app.services.stt_service import transcribe_audio
from app.storage import store

TIMECODE_FRAME_RATE = 30000 / 1001
TIMECODE_FRAME_DURATION = 1001 / 30000


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
        playback_speed = max(0.25, min(float(item.get("playback_speed", 1.0)), 4.0))
        audio_fade_in = max(0.0, min(float(item.get("audio_fade_in", 0.0)), 10.0))
        audio_fade_out = max(0.0, min(float(item.get("audio_fade_out", 0.0)), 10.0))
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
                "audio_start": normalized_audio_start,
                "audio_end": normalized_audio_end,
                "audio_muted": bool(item.get("audio_muted", False)),
                "audio_volume": round(audio_volume, 2),
                "audio_linked": audio_linked,
                "playback_speed": round(playback_speed, 3),
                "audio_fade_in": round(audio_fade_in, 3),
                "audio_fade_out": round(audio_fade_out, 3),
                "score": round(score, 2),
                "tags": tags[:6],
            }
        )
    normalized.sort(key=lambda item: item["order"] if preserve_order else item["start"])
    for index, item in enumerate(normalized, start=1):
        item["order"] = index
    return normalized


def _captions_from_transcript(transcript: list[dict[str, Any]]) -> list[dict[str, Any]]:
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


def analyze_video_job(job_id: str, task: Any | None = None) -> dict[str, Any]:
    settings = get_settings()
    try:
        job = store.load(job_id)
        video_path = Path(job["video_path"])
        work_dir = store.work_dir(job_id)
        audio_path = work_dir / "audio.wav"

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
        captions = _captions_from_transcript(transcript)
        waveform = generate_waveform(audio_path)

        _set_task_state(
            task,
            job_id,
            JobStatus.processing,
            "analyzing_highlights",
            68,
            "하이라이트 분석 중",
            transcript=transcript,
            captions=captions,
            waveform=waveform,
        )
        raw_highlights = _normalize_highlights(
            analyze_highlights(transcript, duration),
            duration,
        )

        _set_task_state(
            task,
            job_id,
            JobStatus.processing,
            "detecting_silence",
            78,
            "침묵 구간 탐지 중",
        )
        silence_ranges = detect_silence(
            audio_path,
            noise_db=settings.silence_noise_db,
            min_duration=settings.silence_min_duration,
        )
        candidate_silences = _silences_overlapping_highlights(
            silence_ranges,
            raw_highlights,
        )

        _set_task_state(
            task,
            job_id,
            JobStatus.processing,
            "checking_visual_changes",
            88,
            "시각적 변화 보호 구간 확인 중",
            silences=silence_ranges_to_dicts(silence_ranges),
        )
        protected_silences = build_protected_silences(video_path, candidate_silences)

        refined = refine_highlights_with_hybrid_cut(
            raw_highlights,
            candidate_silences,
            protected_silences,
            transcript,
        )
        if not refined:
            refined = raw_highlights
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
        )
        return store.load(job_id)
    except Exception as exc:
        store.update(
            job_id,
            status=JobStatus.failed.value,
            stage="failed",
            progress=100,
            message="분석 작업 실패",
            error=str(exc),
        )
        raise


@celery_app.task(bind=True, name="app.tasks.analyze_video")
def analyze_video_task(self: Any, job_id: str) -> dict[str, Any]:
    return analyze_video_job(job_id, self)


def render_video_job(
    job_id: str,
    segments: list[dict[str, Any]],
    options: dict[str, Any] | None = None,
    task: Any | None = None,
) -> dict[str, Any]:
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
        output_name = str(options.get("output_name") or "youtube_highlights.mp4")
        output_path = store.output_dir(job_id) / output_name
        captions = options.get("captions") or []
        if not options.get("include_captions", False):
            captions = []
        rendered_path = render_highlights(
            video_path,
            normalized,
            output_path,
            aspect_ratio=str(options.get("aspect_ratio") or "16:9"),
            captions=captions,
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
        )
        return store.load(job_id)
    except Exception as exc:
        store.update(
            job_id,
            status=JobStatus.failed.value,
            stage="render_failed",
            progress=100,
            message="렌더링 작업 실패",
            error=str(exc),
        )
        raise


@celery_app.task(bind=True, name="app.tasks.render_video")
def render_video_task(
    self: Any,
    job_id: str,
    segments: list[dict[str, Any]],
    options: dict[str, Any] | None = None,
) -> dict[str, Any]:
    return render_video_job(job_id, segments, options, self)
