import uuid
from pathlib import Path

from fastapi import APIRouter, BackgroundTasks, File, Form, HTTPException, UploadFile, status

from app.config import get_settings
from app.schemas import LocalStyleTrainingRequest, StyleProfile, StyleStatus, StyleTrainingResponse
from app.storage import now_iso, safe_filename, store
from app.tasks import train_style_profile_job, train_style_profile_task


router = APIRouter(prefix="/styles", tags=["styles"])


def _load_style_or_404(style_id: str) -> dict:
    try:
        return store.load_style(style_id)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail="style profile not found") from exc


def _queue_style_training(
    *,
    background_tasks: BackgroundTasks,
    style_id: str,
) -> None:
    settings = get_settings()
    if settings.task_runner == "inline":
        background_tasks.add_task(train_style_profile_job, style_id)
    else:
        train_style_profile_task.delay(style_id)


def _save_queued_style_profile(
    *,
    style_id: str,
    name: str,
    inputs: list[dict],
) -> dict:
    now = now_iso()
    profile = {
        "style_id": style_id,
        "name": name.strip() or "Company Reference Style",
        "status": StyleStatus.queued.value,
        "message": "레퍼런스 스타일 학습 대기 중",
        "progress": 0,
        "source_count": len(inputs),
        "ready_source_count": 0,
        "sources": [],
        "reference_inputs": inputs,
        "created_at": now,
        "updated_at": now,
    }
    return store.save_style(style_id, profile)


@router.get("", response_model=list[StyleProfile])
def list_styles() -> list[StyleProfile]:
    return [StyleProfile(**item) for item in store.list_styles()]


@router.get("/{style_id}", response_model=StyleProfile)
def get_style(style_id: str) -> StyleProfile:
    return StyleProfile(**_load_style_or_404(style_id))


@router.post("/train", response_model=StyleTrainingResponse, status_code=status.HTTP_202_ACCEPTED)
async def train_style(
    background_tasks: BackgroundTasks,
    name: str = Form("Company Reference Style"),
    urls: list[str] | None = Form(None),
    files: list[UploadFile] | None = File(None),
) -> StyleTrainingResponse:
    settings = get_settings()
    style_id = uuid.uuid4().hex
    reference_dir = store.style_upload_dir(style_id)
    inputs: list[dict] = []

    max_bytes = settings.upload_max_mb * 1024 * 1024
    for file_index, file in enumerate(files or [], start=1):
        filename = safe_filename(file.filename or f"reference_{file_index}.mp4")
        target = reference_dir / filename
        total = 0
        with target.open("wb") as output:
            while chunk := await file.read(1024 * 1024):
                total += len(chunk)
                if total > max_bytes:
                    raise HTTPException(
                        status_code=413,
                        detail=f"reference upload exceeds {settings.upload_max_mb}MB limit",
                    )
                output.write(chunk)
        inputs.append(
            {
                "kind": "file",
                "label": filename,
                "path": str(target),
                "url": None,
            }
        )

    for url_index, raw_url in enumerate(urls or [], start=1):
        url = raw_url.strip()
        if not url:
            continue
        inputs.append(
            {
                "kind": "url",
                "label": f"URL {url_index}",
                "path": None,
                "url": url,
            }
        )

    if not inputs:
        raise HTTPException(status_code=400, detail="at least one reference file or URL is required")

    _save_queued_style_profile(style_id=style_id, name=name, inputs=inputs)
    _queue_style_training(background_tasks=background_tasks, style_id=style_id)

    saved = store.load_style(style_id)
    return StyleTrainingResponse(
        style_id=style_id,
        status=StyleStatus(saved["status"]),
        progress=int(saved.get("progress") or 0),
        message=str(saved.get("message") or ""),
        profile=StyleProfile(**saved),
    )


@router.post("/train-local", response_model=StyleTrainingResponse, status_code=status.HTTP_202_ACCEPTED)
def train_local_style(
    payload: LocalStyleTrainingRequest,
    background_tasks: BackgroundTasks,
) -> StyleTrainingResponse:
    style_id = uuid.uuid4().hex
    inputs: list[dict] = []
    for file_index, raw_path in enumerate(payload.file_paths, start=1):
        if not raw_path.strip():
            continue
        source_path = Path(raw_path).expanduser()
        try:
            source_path = source_path.resolve(strict=True)
        except FileNotFoundError as exc:
            raise HTTPException(status_code=404, detail=f"reference file not found: {raw_path}") from exc
        if not source_path.is_file():
            raise HTTPException(status_code=400, detail=f"reference path must be a file: {raw_path}")
        inputs.append(
            {
                "kind": "file",
                "label": source_path.name or f"Reference {file_index}",
                "path": str(source_path),
                "url": None,
            }
        )

    for url_index, raw_url in enumerate(payload.urls, start=1):
        url = raw_url.strip()
        if not url:
            continue
        inputs.append(
            {
                "kind": "url",
                "label": f"URL {url_index}",
                "path": None,
                "url": url,
            }
        )

    if not inputs:
        raise HTTPException(status_code=400, detail="at least one reference file path or URL is required")

    _save_queued_style_profile(
        style_id=style_id,
        name=payload.name,
        inputs=inputs,
    )
    _queue_style_training(background_tasks=background_tasks, style_id=style_id)
    saved = store.load_style(style_id)
    return StyleTrainingResponse(
        style_id=style_id,
        status=StyleStatus(saved["status"]),
        progress=int(saved.get("progress") or 0),
        message=str(saved.get("message") or ""),
        profile=StyleProfile(**saved),
    )


@router.post("/{style_id}/activate", response_model=StyleProfile)
def activate_style(style_id: str) -> StyleProfile:
    profile = _load_style_or_404(style_id)
    if profile.get("status") != StyleStatus.ready.value:
        raise HTTPException(status_code=409, detail="style profile is not ready")
    return StyleProfile(**profile)
