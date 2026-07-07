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
        start = max(0.0, min(float(item["start"]), duration))
        end = max(0.0, min(float(item["end"]), duration))
        if end <= start:
            continue
        normalized.append(
            {
                "order": int(item.get("order") or index),
                "start": round(start, 1),
                "end": round(end, 1),
                "reason": str(item.get("reason", "AI 추천 구간")),
                "script": str(item.get("script", "")),
                "source": str(item.get("source", "ai")),
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
            self,
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
