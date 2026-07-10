import json
import os
from datetime import UTC, datetime, timedelta
from pathlib import Path
from types import SimpleNamespace

from fastapi.testclient import TestClient

from app.main import app
from app.routers import system as system_router
from app.services.storage_service import cleanup_safe_storage, collect_storage_usage


def _write_file(path: Path, size: int, modified_at: datetime | None = None) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"x" * size)
    if modified_at is not None:
        timestamp = modified_at.timestamp()
        os.utime(path, (timestamp, timestamp))
    return path


def _write_job(
    root: Path,
    job_id: str,
    *,
    status: str,
    updated_at: datetime,
    work_size: int,
) -> dict[str, Path]:
    job_dir = root / "jobs" / job_id
    work = _write_file(job_dir / "work" / "audio.wav", work_size)
    source = _write_file(job_dir / "uploads" / "source.mxf", 11)
    output = _write_file(job_dir / "outputs" / "render.mp4", 13)
    job_file = job_dir / "job.json"
    job_file.write_text(
        json.dumps(
            {
                "job_id": job_id,
                "status": status,
                "updated_at": updated_at.isoformat(),
            }
        ),
        encoding="utf-8",
    )
    return {
        "work": work,
        "source": source,
        "output": output,
        "job": job_file,
    }


def test_cleanup_removes_only_old_rebuildable_cache(tmp_path: Path) -> None:
    now = datetime(2026, 7, 10, 12, tzinfo=UTC)
    old = now - timedelta(days=2)
    recent = now - timedelta(hours=2)
    finished = _write_job(
        tmp_path,
        "finished",
        status="rendered",
        updated_at=old,
        work_size=40,
    )
    active = _write_job(
        tmp_path,
        "active",
        status="rendered",
        updated_at=old,
        work_size=20,
    )
    processing = _write_job(
        tmp_path,
        "processing",
        status="processing",
        updated_at=old,
        work_size=30,
    )
    recent_job = _write_job(
        tmp_path,
        "recent",
        status="completed",
        updated_at=recent,
        work_size=25,
    )
    old_preview = _write_file(
        tmp_path / "preview_proxies" / "old.mp4",
        10,
        old,
    )
    recent_preview = _write_file(
        tmp_path / "preview_proxies" / "recent.mp4",
        15,
        recent,
    )
    style_profile = _write_file(
        tmp_path / "styles" / "style-1" / "style.json",
        7,
    )

    usage = collect_storage_usage(
        tmp_path,
        active_job_id="active",
        retention_hours=24,
        now=now,
    )
    categories = {item["key"]: item for item in usage["categories"]}

    assert usage["reclaimable_bytes"] == 50
    assert categories["preview_cache"]["reclaimable_bytes"] == 10
    assert categories["analysis_cache"]["reclaimable_bytes"] == 40
    assert categories["source_copies"]["protected"] is True
    assert categories["render_outputs"]["protected"] is True

    result = cleanup_safe_storage(
        tmp_path,
        active_job_id="active",
        retention_hours=24,
        now=now,
    )

    assert result["freed_bytes"] == 50
    assert result["deleted_files"] == 2
    assert result["skipped_files"] == 0
    assert not old_preview.exists()
    assert not finished["work"].exists()
    assert recent_preview.exists()
    assert active["work"].exists()
    assert processing["work"].exists()
    assert recent_job["work"].exists()
    assert style_profile.exists()
    for job in (finished, active, processing, recent_job):
        assert job["source"].exists()
        assert job["output"].exists()
        assert job["job"].exists()
    assert result["after"]["reclaimable_bytes"] == 0


def test_storage_api_never_accepts_a_cleanup_path(
    tmp_path: Path,
    monkeypatch,
) -> None:
    now = datetime.now(UTC)
    old = now - timedelta(days=2)
    old_preview = _write_file(
        tmp_path / "preview_proxies" / "old.mp4",
        17,
        old,
    )
    monkeypatch.setattr(
        system_router,
        "get_settings",
        lambda: SimpleNamespace(data_dir=tmp_path),
    )
    client = TestClient(app)

    response = client.get("/api/system/storage?retention_hours=24")
    assert response.status_code == 200
    assert response.json()["reclaimable_bytes"] == 17

    cleanup = client.post(
        "/api/system/storage/cleanup",
        json={
            "active_job_id": "current-job",
            "retention_hours": 24,
            "path": "C:/Users/seung/Videos",
        },
    )

    assert cleanup.status_code == 422
    assert old_preview.exists()

    cleanup = client.post(
        "/api/system/storage/cleanup",
        json={"active_job_id": "current-job", "retention_hours": 24},
    )
    assert cleanup.status_code == 200
    assert cleanup.json()["freed_bytes"] == 17
    assert not old_preview.exists()
