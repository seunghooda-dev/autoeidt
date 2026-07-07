import uuid
from pathlib import Path

from fastapi import APIRouter, File, HTTPException, UploadFile, status
from fastapi.responses import FileResponse

from app.config import get_settings
from app.schemas import (
    JobStatus,
    JobStatusResponse,
    RenderRequest,
    RenderResponse,
    TimelineResponse,
    UploadJobResponse,
)
from app.storage import now_iso, safe_filename, store
from app.tasks import analyze_video_task, render_video_task


router = APIRouter(prefix="/jobs", tags=["jobs"])


def _load_job_or_404(job_id: str) -> dict:
    try:
        return store.load(job_id)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail="job not found") from exc


@router.post("/upload", response_model=UploadJobResponse, status_code=status.HTTP_202_ACCEPTED)
async def upload_video(file: UploadFile = File(...)) -> UploadJobResponse:
    settings = get_settings()
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

    job = {
        "job_id": job_id,
        "status": JobStatus.queued.value,
        "stage": "queued",
        "progress": 0,
        "message": "분석 작업 등록 중",
        "original_filename": file.filename,
        "video_path": str(video_path),
        "audio_path": None,
        "duration": None,
        "transcript": [],
        "segments": [],
        "render_path": None,
        "render_url": None,
        "error": None,
        "created_at": now_iso(),
        "updated_at": now_iso(),
    }
    store.save(job_id, job)

    task = analyze_video_task.delay(job_id)
    store.update(job_id, celery_task_id=task.id, message="분석 작업 대기 중")

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
    )


@router.get("/{job_id}/source")
def stream_source(job_id: str) -> FileResponse:
    job = _load_job_or_404(job_id)
    path = Path(job["video_path"])
    if not path.exists():
        raise HTTPException(status_code=404, detail="source video file not found")
    return FileResponse(path, media_type="video/mp4", filename=path.name)


@router.post("/{job_id}/render", response_model=RenderResponse, status_code=status.HTTP_202_ACCEPTED)
def render_job(job_id: str, payload: RenderRequest) -> RenderResponse:
    _load_job_or_404(job_id)
    segments = [segment.model_dump() for segment in payload.segments]
    task = render_video_task.delay(job_id, segments)
    store.update(
        job_id,
        status=JobStatus.rendering.value,
        stage="render_queued",
        progress=0,
        message="렌더링 작업 대기 중",
        render_task_id=task.id,
        segments=segments,
    )
    return RenderResponse(
        job_id=job_id,
        render_task_id=task.id,
        status=JobStatus.rendering,
        stage="render_queued",
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
        filename=f"{job_id}_youtube_highlights.mp4",
    )
