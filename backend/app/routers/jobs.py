import uuid
from pathlib import Path

from fastapi import APIRouter, BackgroundTasks, File, Form, HTTPException, UploadFile, status
from fastapi.responses import FileResponse

from app.config import get_settings
from app.schemas import (
    BatchRenderRequest,
    JobStatus,
    JobStatusResponse,
    LocalImportRequest,
    LocalPreviewResponse,
    MediaProbeRequest,
    MediaProbeResponse,
    ProjectResponse,
    ProjectState,
    RenderRequest,
    RenderResponse,
    TimelineResponse,
    UploadJobResponse,
)
from app.services.ffmpeg_service import FFmpegError, create_preview_proxy, probe_media_info
from app.storage import now_iso, safe_filename, store
from app.tasks import (
    analyze_video_job,
    analyze_video_task,
    render_batch_video_job,
    render_batch_video_task,
    render_video_job,
    render_video_task,
)


router = APIRouter(prefix="/jobs", tags=["jobs"])


def _load_job_or_404(job_id: str) -> dict:
    try:
        return store.load(job_id)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail="job not found") from exc


def _load_ready_style_profile(style_id: str | None) -> dict | None:
    if not style_id:
        return None
    try:
        style_profile = store.load_style(style_id)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail="style profile not found") from exc
    if style_profile.get("status") != "ready":
        raise HTTPException(status_code=409, detail="style profile is not ready")
    return style_profile


def _resolve_local_file(path: str) -> Path:
    source_path = Path(path).expanduser()
    try:
        source_path = source_path.resolve(strict=True)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail="local source file not found") from exc
    if not source_path.is_file():
        raise HTTPException(status_code=400, detail="local source path must be a file")
    return source_path


def _source_media_type(path: Path) -> str:
    suffix = path.suffix.lower()
    if suffix == ".mxf":
        return "application/mxf"
    if suffix in {".mov", ".qt"}:
        return "video/quicktime"
    if suffix in {".mkv", ".mk3d"}:
        return "video/x-matroska"
    if suffix in {".ts", ".m2ts", ".mts"}:
        return "video/mp2t"
    if suffix in {".avi"}:
        return "video/x-msvideo"
    if suffix in {".wmv", ".asf"}:
        return "video/x-ms-wmv"
    return "video/mp4"


def _queue_analysis(
    *,
    background_tasks: BackgroundTasks,
    job_id: str,
) -> str:
    settings = get_settings()
    if settings.task_runner == "inline":
        task_id = f"inline-analyze-{job_id}"
        store.update(
            job_id,
            celery_task_id=task_id,
            message="로컬 분석 작업 대기 중",
        )
        background_tasks.add_task(analyze_video_job, job_id)
    else:
        task = analyze_video_task.delay(job_id)
        task_id = task.id
        store.update(job_id, celery_task_id=task_id, message="분석 작업 대기 중")
    return task_id


def _create_analysis_job(
    *,
    job_id: str,
    original_filename: str,
    video_path: Path,
    style_profile: dict | None,
    import_mode: str,
) -> None:
    job = {
        "job_id": job_id,
        "status": JobStatus.queued.value,
        "stage": "queued",
        "progress": 0,
        "message": "분석 작업 등록 중",
        "original_filename": original_filename,
        "video_path": str(video_path),
        "import_mode": import_mode,
        "audio_path": None,
        "duration": None,
        "transcript": [],
        "segments": [],
        "render_path": None,
        "render_url": None,
        "error": None,
        "style_profile": style_profile,
        "created_at": now_iso(),
        "updated_at": now_iso(),
    }
    store.save(job_id, job)


@router.post("/upload", response_model=UploadJobResponse, status_code=status.HTTP_202_ACCEPTED)
async def upload_video(
    background_tasks: BackgroundTasks,
    file: UploadFile = File(...),
    style_id: str | None = Form(None),
) -> UploadJobResponse:
    settings = get_settings()
    style_profile = _load_ready_style_profile(style_id)

    job_id = uuid.uuid4().hex
    upload_dir = store.upload_dir(job_id)
    filename = safe_filename(file.filename or "video.mp4")
    video_path = upload_dir / filename

    max_bytes = settings.upload_max_mb * 1024 * 1024
    total = 0
    with video_path.open("wb") as output:
        while chunk := await file.read(1024 * 1024):
            total += len(chunk)
            if total > max_bytes:
                raise HTTPException(
                    status_code=413,
                    detail=f"upload exceeds {settings.upload_max_mb}MB limit",
                )
            output.write(chunk)

    _create_analysis_job(
        job_id=job_id,
        original_filename=file.filename or filename,
        video_path=video_path,
        style_profile=style_profile,
        import_mode="uploaded_copy",
    )
    _queue_analysis(background_tasks=background_tasks, job_id=job_id)

    return UploadJobResponse(
        job_id=job_id,
        status=JobStatus.queued,
        stage="queued",
        progress=0,
    )


@router.post("/probe-local", response_model=MediaProbeResponse)
def probe_local_media(payload: MediaProbeRequest) -> MediaProbeResponse:
    source_path = _resolve_local_file(payload.path)
    try:
        return MediaProbeResponse(**probe_media_info(source_path))
    except FFmpegError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc


@router.post("/preview-local", response_model=LocalPreviewResponse)
def create_local_preview(payload: MediaProbeRequest) -> LocalPreviewResponse:
    source_path = _resolve_local_file(payload.path)
    try:
        preview_path, cached = create_preview_proxy(source_path)
    except FFmpegError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    return LocalPreviewResponse(
        preview_url=f"/api/jobs/preview/{preview_path.name}",
        cached=cached,
    )


@router.get("/preview/{filename}")
def stream_preview_proxy(filename: str) -> FileResponse:
    if "/" in filename or "\\" in filename or not filename.endswith(".mp4"):
        raise HTTPException(status_code=400, detail="invalid preview filename")
    path = get_settings().data_dir / "preview_proxies" / filename
    if not path.exists():
        raise HTTPException(status_code=404, detail="preview file not found")
    return FileResponse(path, media_type="video/mp4", filename=filename)


@router.post("/import-local", response_model=UploadJobResponse, status_code=status.HTTP_202_ACCEPTED)
def import_local_video(
    payload: LocalImportRequest,
    background_tasks: BackgroundTasks,
) -> UploadJobResponse:
    source_path = _resolve_local_file(payload.path)
    style_profile = _load_ready_style_profile(payload.style_id)
    job_id = uuid.uuid4().hex
    _create_analysis_job(
        job_id=job_id,
        original_filename=payload.display_name or source_path.name,
        video_path=source_path,
        style_profile=style_profile,
        import_mode="local_path",
    )
    _queue_analysis(background_tasks=background_tasks, job_id=job_id)
    return UploadJobResponse(
        job_id=job_id,
        status=JobStatus.queued,
        stage="queued",
        progress=0,
    )


@router.get("/{job_id}", response_model=JobStatusResponse)
def get_job(job_id: str) -> JobStatusResponse:
    job = _load_job_or_404(job_id)
    return JobStatusResponse(**job)


@router.get("/{job_id}/timeline", response_model=TimelineResponse)
def get_timeline(job_id: str) -> TimelineResponse:
    job = _load_job_or_404(job_id)
    if job.get("status") not in {JobStatus.completed.value, JobStatus.rendered.value}:
        raise HTTPException(status_code=409, detail="timeline is not ready")
    return TimelineResponse(
        job_id=job_id,
        duration=float(job.get("duration") or 0),
        segments=job.get("segments") or [],
        transcript=job.get("transcript") or [],
        captions=job.get("captions") or [],
        waveform=job.get("waveform") or [],
    )


@router.get("/{job_id}/project", response_model=ProjectResponse)
def get_project(job_id: str) -> ProjectResponse:
    job = _load_job_or_404(job_id)
    return ProjectResponse(
        job_id=job_id,
        name=job.get("project_name") or job.get("original_filename") or "AutoEdit Project",
        original_filename=job.get("original_filename"),
        duration=float(job.get("duration") or 0),
        segments=job.get("segments") or [],
        captions=job.get("captions") or [],
        waveform=job.get("waveform") or [],
    )


@router.post("/{job_id}/project", response_model=ProjectResponse)
def save_project(job_id: str, payload: ProjectState) -> ProjectResponse:
    _load_job_or_404(job_id)
    updated = store.update(
        job_id,
        project_name=payload.name,
        duration=payload.duration,
        segments=[segment.model_dump() for segment in payload.segments],
        captions=[caption.model_dump() for caption in payload.captions],
        waveform=payload.waveform,
    )
    return ProjectResponse(
        job_id=job_id,
        name=updated.get("project_name") or payload.name,
        original_filename=updated.get("original_filename"),
        duration=float(updated.get("duration") or 0),
        segments=updated.get("segments") or [],
        captions=updated.get("captions") or [],
        waveform=updated.get("waveform") or [],
    )


@router.get("/{job_id}/source")
def stream_source(job_id: str) -> FileResponse:
    job = _load_job_or_404(job_id)
    path = Path(job["video_path"])
    if not path.exists():
        raise HTTPException(status_code=404, detail="source video file not found")
    return FileResponse(path, media_type=_source_media_type(path), filename=path.name)


@router.post("/{job_id}/render", response_model=RenderResponse, status_code=status.HTTP_202_ACCEPTED)
def render_job(
    job_id: str,
    payload: RenderRequest,
    background_tasks: BackgroundTasks,
) -> RenderResponse:
    _load_job_or_404(job_id)
    settings = get_settings()
    segments = [segment.model_dump() for segment in payload.segments]
    render_options = {
        "captions": [caption.model_dump() for caption in payload.captions],
        "caption_style": payload.caption_style.model_dump(),
        "aspect_ratio": payload.aspect_ratio,
        "include_captions": payload.include_captions,
        "output_name": safe_filename(payload.output_name or "youtube_highlights.mp4"),
    }
    if settings.task_runner == "inline":
        task_id = f"inline-render-{job_id}"
        background_tasks.add_task(render_video_job, job_id, segments, render_options)
    else:
        task = render_video_task.delay(job_id, segments, render_options)
        task_id = task.id
    store.update(
        job_id,
        status=JobStatus.rendering.value,
        stage="render_queued",
        progress=0,
        message="렌더링 작업 대기 중",
        render_task_id=task_id,
        segments=segments,
        captions=render_options["captions"],
        render_options=render_options,
    )
    return RenderResponse(
        job_id=job_id,
        render_task_id=task_id,
        status=JobStatus.rendering,
        stage="render_queued",
    )


@router.post("/{job_id}/batch-render", response_model=RenderResponse, status_code=status.HTTP_202_ACCEPTED)
def batch_render_job(
    job_id: str,
    payload: BatchRenderRequest,
    background_tasks: BackgroundTasks,
) -> RenderResponse:
    _load_job_or_404(job_id)
    if not payload.items:
        raise HTTPException(status_code=400, detail="at least one shorts item is required")
    settings = get_settings()
    items = [
        {
            "label": item.label,
            "segments": [segment.model_dump() for segment in item.segments],
            "output_name": safe_filename(item.output_name or "shorts.mp4"),
        }
        for item in payload.items
    ]
    render_options = {
        "captions": [caption.model_dump() for caption in payload.captions],
        "caption_style": payload.caption_style.model_dump(),
        "aspect_ratio": payload.aspect_ratio,
        "include_captions": payload.include_captions,
    }
    if settings.task_runner == "inline":
        task_id = f"inline-batch-render-{job_id}"
        background_tasks.add_task(render_batch_video_job, job_id, items, render_options)
    else:
        task = render_batch_video_task.delay(job_id, items, render_options)
        task_id = task.id
    store.update(
        job_id,
        status=JobStatus.rendering.value,
        stage="batch_render_queued",
        progress=0,
        message="쇼츠 일괄 렌더링 대기 중",
        render_task_id=task_id,
        batch_render_request=items,
        render_options=render_options,
    )
    return RenderResponse(
        job_id=job_id,
        render_task_id=task_id,
        status=JobStatus.rendering,
        stage="batch_render_queued",
    )


@router.get("/{job_id}/download")
def download_render(job_id: str) -> FileResponse:
    job = _load_job_or_404(job_id)
    render_path = job.get("render_path")
    if not render_path:
        raise HTTPException(status_code=404, detail="rendered video not available")
    path = Path(render_path)
    if not path.exists():
        raise HTTPException(status_code=404, detail="rendered video file not found")
    return FileResponse(
        path,
        media_type="video/mp4",
        filename=path.name,
    )


@router.get("/{job_id}/download/{filename}")
def download_named_render(job_id: str, filename: str) -> FileResponse:
    job = _load_job_or_404(job_id)
    safe_name = safe_filename(filename)
    path = store.output_dir(job_id) / safe_name
    if not path.exists():
        raise HTTPException(status_code=404, detail="rendered video file not found")
    return FileResponse(
        path,
        media_type="video/mp4",
        filename=path.name,
    )
