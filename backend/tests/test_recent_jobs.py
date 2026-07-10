import json
from pathlib import Path

from fastapi.testclient import TestClient

from app.main import app
from app.routers import jobs
from app.storage import JobStore


client = TestClient(app)


def _write_job(
    store: JobStore,
    job_id: str,
    *,
    status: str,
    updated_at: str,
    **fields,
) -> None:
    payload = {
        "job_id": job_id,
        "status": status,
        "stage": status,
        "progress": 40 if status == "processing" else 100,
        "message": status,
        "video_path": "C:/media/source.mxf",
        "duration": 60,
        "segments": [],
        "render_path": None,
        "render_url": None,
        "created_at": updated_at,
        "updated_at": updated_at,
        **fields,
    }
    path = store.job_file(job_id)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload), encoding="utf-8")


def test_job_store_lists_newest_first_and_recovers_interrupted_jobs(
    tmp_path: Path,
) -> None:
    store = JobStore(root=tmp_path)
    _write_job(
        store,
        "older-complete",
        status="completed",
        updated_at="2026-07-08T10:00:00+00:00",
        render_path="C:/outputs/finished.mp4",
    )
    _write_job(
        store,
        "newer-active",
        status="processing",
        updated_at="2026-07-09T10:00:00+00:00",
        stage="transcribing",
        render_path="C:/outputs/previous.mp4",
    )

    assert [item["job_id"] for item in store.list_jobs()] == [
        "newer-active",
        "older-complete",
    ]

    recovered = store.recover_interrupted_jobs()
    interrupted = store.load("newer-active")
    completed = store.load("older-complete")

    assert recovered == 1
    assert interrupted["status"] == "cancelled"
    assert interrupted["stage"] == "interrupted"
    assert interrupted["render_path"] == "C:/outputs/previous.mp4"
    assert interrupted["error"] is None
    assert completed["status"] == "completed"


def test_recent_jobs_api_reports_resume_evidence(
    tmp_path: Path,
    monkeypatch,
) -> None:
    source = tmp_path / "source.mxf"
    source.write_bytes(b"source")
    render = tmp_path / "render.mp4"
    render.write_bytes(b"render")

    class FakeStore:
        def list_jobs(self, limit: int = 30) -> list[dict]:
            assert limit == 5
            return [
                {
                    "job_id": "rendered-job",
                    "status": "rendered",
                    "stage": "rendered",
                    "progress": 100,
                    "message": "done",
                    "project_name": "Evening News",
                    "original_filename": "source.mxf",
                    "video_path": str(source),
                    "duration": 120,
                    "import_mode": "local_path",
                    "segments": [
                        {"order": 1, "start": 0, "end": 10, "reason": "lead"}
                    ],
                    "render_path": str(render),
                    "render_url": "/api/jobs/rendered-job/download",
                    "created_at": "2026-07-10T10:00:00+00:00",
                    "updated_at": "2026-07-10T11:00:00+00:00",
                }
            ]

    monkeypatch.setattr(jobs, "store", FakeStore())

    response = client.get("/api/jobs?limit=5")

    assert response.status_code == 200
    payload = response.json()[0]
    assert payload["job_id"] == "rendered-job"
    assert payload["project_name"] == "Evening News"
    assert payload["source_exists"] is True
    assert payload["has_timeline"] is True
    assert payload["segment_count"] == 1
    assert payload["render_exists"] is True
    assert payload["can_resume"] is True
