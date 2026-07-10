from fastapi import APIRouter, Query

from app.config import get_settings
from app.schemas import (
    StorageCleanupRequest,
    StorageCleanupResponse,
    StorageUsageResponse,
)
from app.services.storage_service import cleanup_safe_storage, collect_storage_usage


router = APIRouter(prefix="/system", tags=["system"])


@router.get("/storage", response_model=StorageUsageResponse)
def storage_usage(
    active_job_id: str | None = Query(default=None, max_length=64),
    retention_hours: int = Query(default=24, ge=1, le=720),
) -> StorageUsageResponse:
    settings = get_settings()
    return StorageUsageResponse(
        **collect_storage_usage(
            settings.data_dir,
            active_job_id=active_job_id,
            retention_hours=retention_hours,
        )
    )


@router.post("/storage/cleanup", response_model=StorageCleanupResponse)
def cleanup_storage(payload: StorageCleanupRequest) -> StorageCleanupResponse:
    settings = get_settings()
    return StorageCleanupResponse(
        **cleanup_safe_storage(
            settings.data_dir,
            active_job_id=payload.active_job_id,
            retention_hours=payload.retention_hours,
        )
    )
