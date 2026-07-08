from pathlib import Path
from typing import Any

from app.celery_app import celery_app
from app.config import get_settings
from app.schemas import JobStatus
from app.services.ffmpeg_service import (
    detect_scene_changes,
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
from app.storage import now_iso, safe_filename, store

TIMECODE_FRAME_RATE = 30000 / 1001
TIMECODE_FRAME_DURATION = 1001 / 30000


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
    total = 0.0
    for segment in segments:
        start = float(segment.get("start", 0.0))
        end = float(segment.get("end", start))
        speed = max(0.25, float(segment.get("playback_speed", 1.0) or 1.0))
        total += max(0.0, end - start) / speed
    return round(total, 3)


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
        waveform = _generate_waveform_for_analysis(audio_path, analysis_warnings)

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
            88,
            "시각적 변화 보호 구간 확인 중",
            silences=silence_ranges_to_dicts(silence_ranges),
        )
        scene_points = _detect_scene_points_for_analysis(
            video_path,
            settings.scene_change_threshold,
            analysis_warnings,
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
                    "duration_seconds": render_duration_seconds,
                    "size_bytes": render_size_bytes,
                    "warnings": render_warnings,
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
            render_duration_seconds=rendered_items[0]["duration_seconds"],
            render_size_bytes=rendered_items[0]["size_bytes"],
            render_warnings=[
                f"{item['label']}: {warning}"
                for item in rendered_items
                for warning in item.get("warnings", [])
            ],
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
