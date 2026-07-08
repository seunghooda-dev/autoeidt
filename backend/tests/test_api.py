from fastapi.testclient import TestClient

from app.main import app
from app.routers import jobs


client = TestClient(app)


def test_health_endpoint() -> None:
    response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_timeline_returns_not_found_for_unknown_job() -> None:
    response = client.get("/api/jobs/missing/timeline")

    assert response.status_code == 404


def test_local_import_returns_not_found_for_missing_file() -> None:
    response = client.post(
        "/api/jobs/import-local",
        json={"path": "C:/definitely/missing/source.mp4", "display_name": "missing.mp4"},
    )

    assert response.status_code == 404


def test_local_probe_returns_not_found_for_missing_file() -> None:
    response = client.post(
        "/api/jobs/probe-local",
        json={"path": "C:/definitely/missing/source.mxf"},
    )

    assert response.status_code == 404


def test_batch_render_returns_not_found_for_unknown_job() -> None:
    response = client.post(
        "/api/jobs/missing/batch-render",
        json={
            "items": [
                {
                    "label": "Shorts 01",
                    "output_name": "shorts_01.mp4",
                    "segments": [
                        {"order": 1, "start": 0, "end": 10, "reason": "test"}
                    ],
                }
            ]
        },
    )

    assert response.status_code == 404


def test_job_status_includes_render_paths_and_batch_outputs(monkeypatch) -> None:
    class FakeStore:
        def load(self, job_id: str) -> dict:
            assert job_id == "rendered-job"
            return {
                "job_id": job_id,
                "status": "rendered",
                "stage": "batch_rendered",
                "progress": 100,
                "message": "done",
                "duration": 120,
                "segments": [],
                "render_path": "C:/AutoEdit/outputs/shorts_01.mp4",
                "render_url": "/api/jobs/rendered-job/download/shorts_01.mp4",
                "render_duration_seconds": 45.5,
                "render_size_bytes": 123456,
                "batch_render_items": [
                    {
                        "label": "Shorts 01",
                        "path": "C:/AutoEdit/outputs/shorts_01.mp4",
                        "url": "/api/jobs/rendered-job/download/shorts_01.mp4",
                        "output_name": "shorts_01.mp4",
                        "duration_seconds": 45.5,
                        "size_bytes": 123456,
                        "segments": [],
                    },
                    {
                        "label": "Shorts 02",
                        "path": "C:/AutoEdit/outputs/shorts_02.mp4",
                        "url": "/api/jobs/rendered-job/download/shorts_02.mp4",
                        "output_name": "shorts_02.mp4",
                        "duration_seconds": 61.2,
                        "size_bytes": 234567,
                        "segments": [],
                    },
                ],
            }

    monkeypatch.setattr(jobs, "store", FakeStore())

    response = client.get("/api/jobs/rendered-job")

    assert response.status_code == 200
    payload = response.json()
    assert payload["render_path"] == "C:/AutoEdit/outputs/shorts_01.mp4"
    assert payload["render_duration_seconds"] == 45.5
    assert payload["render_size_bytes"] == 123456
    assert len(payload["batch_render_items"]) == 2
    assert payload["batch_render_items"][1]["path"].endswith("shorts_02.mp4")
    assert payload["batch_render_items"][1]["duration_seconds"] == 61.2
    assert payload["batch_render_items"][1]["size_bytes"] == 234567
