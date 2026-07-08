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
from app.services.llm_service import analyze_highlights, fallback_review_highlights
from app.services.reference_style import (
    analyze_reference_video,
    build_style_profile,
    download_reference_url,
)
from app.services.stt_service import transcribe_audio
from app.storage import now_iso, store

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
        playback_speed = max(0.25, min(float(item.get("playback_speed", 1.0)), 4.0))
        video_fade_in = max(0.0, min(float(item.get("video_fade_in", 0.0)), 10.0))
        video_fade_out = max(0.0, min(float(item.get("video_fade_out", 0.0)), 10.0))
        color_brightness = max(-0.3, min(float(item.get("color_brightness", 0.0)), 0.3))
        color_contrast = max(0.5, min(float(item.get("color_contrast", 1.0)), 1.8))
        color_saturation = max(0.0, min(float(item.get("color_saturation", 1.0)), 2.0))
        audio_fade_in = max(0.0, min(float(item.get("audio_fade_in", 0.0)), 10.0))
        audio_fade_out = max(0.0, min(float(item.get("audio_fade_out", 0.0)), 10.0))
        audio_channel_1_enabled = bool(item.get("audio_channel_1_enabled", True))
        audio_channel_2_enabled = bool(item.get("audio_channel_2_enabled", True))
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
                "audio_start": normalized_audio_start,
                "audio_end": normalized_audio_end,
                "audio_muted": bool(item.get("audio_muted", False)),
                "audio_volume": round(audio_volume, 2),
                "audio_pan": round(audio_pan, 2),
                "audio_normalize": bool(item.get("audio_normalize", False)),
                "audio_linked": audio_linked,
                "audio_channel_1_enabled": audio_channel_1_enabled,
                "audio_channel_2_enabled": audio_channel_2_enabled,
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


def analyze_video_job(job_id: str, task: Any | None = None) -> dict[str, Any]:
    settings = get_settings()
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
            analysis_warnings=analysis_warnings,
        )
        raw_highlights = _normalize_highlights(
            analyze_highlights(transcript, duration, style_profile),
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
        silence_ranges = detect_silence(
            audio_path,
            noise_db=settings.silence_noise_db,
            min_duration=min_silence,
        )
        if transcript and all(item.get("source") == "fallback_stt" for item in transcript):
            raw_highlights = _normalize_highlights(
                fallback_review_highlights(
                    duration,
                    settings.target_highlight_seconds_min,
                    settings.target_highlight_seconds_max,
                    silence_ranges=silence_ranges,
                ),
                duration,
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
            style_profile=style_profile,
            analysis_warnings=analysis_warnings,
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
        caption_style = options.get("caption_style") or {}
        rendered_path = render_highlights(
            video_path,
            normalized,
            output_path,
            aspect_ratio=str(options.get("aspect_ratio") or "16:9"),
            captions=captions,
            caption_style=caption_style,
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


def render_batch_video_job(
    job_id: str,
    items: list[dict[str, Any]],
    options: dict[str, Any] | None = None,
    task: Any | None = None,
) -> dict[str, Any]:
    try:
        options = options or {}
        job = store.load(job_id)
        duration = float(job.get("duration") or 0)
        video_path = Path(job["video_path"])
        captions = options.get("captions") or []
        if not options.get("include_captions", True):
            captions = []
        caption_style = options.get("caption_style") or {}
        rendered_items: list[dict[str, Any]] = []
        total = max(len(items), 1)
        for index, item in enumerate(items, start=1):
            normalized = _normalize_highlights(
                list(item.get("segments") or []),
                duration or 1_000_000.0,
                preserve_order=True,
            )
            if not normalized:
                continue
            output_name = str(item.get("output_name") or f"shorts_{index:02}.mp4")
            output_path = store.output_dir(job_id) / output_name
            progress = 10 + int(index / total * 80)
            _set_task_state(
                task,
                job_id,
                JobStatus.rendering,
                "batch_rendering",
                progress,
                f"쇼츠 {index}/{total} 렌더링 중",
                batch_render_items=rendered_items,
            )
            rendered_path = render_highlights(
                video_path,
                normalized,
                output_path,
                aspect_ratio=str(options.get("aspect_ratio") or "9:16"),
                captions=captions,
                caption_style=caption_style,
            )
            rendered_items.append(
                {
                    "label": str(item.get("label") or f"Shorts {index:02}"),
                    "path": str(rendered_path),
                    "url": f"/api/jobs/{job_id}/download/{rendered_path.name}",
                    "output_name": rendered_path.name,
                    "segments": normalized,
                }
            )
        if not rendered_items:
            raise ValueError("렌더링할 쇼츠 후보가 없습니다.")

        _set_task_state(
            task,
            job_id,
            JobStatus.rendered,
            "batch_rendered",
            100,
            "쇼츠 일괄 렌더링 완료",
            batch_render_items=rendered_items,
            render_path=rendered_items[0]["path"],
            render_url=rendered_items[0]["url"],
        )
        return store.load(job_id)
    except Exception as exc:
        store.update(
            job_id,
            status=JobStatus.failed.value,
            stage="batch_render_failed",
            progress=100,
            message="쇼츠 일괄 렌더링 실패",
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


@celery_app.task(bind=True, name="app.tasks.render_batch_video")
def render_batch_video_task(
    self: Any,
    job_id: str,
    items: list[dict[str, Any]],
    options: dict[str, Any] | None = None,
) -> dict[str, Any]:
    return render_batch_video_job(job_id, items, options, self)
