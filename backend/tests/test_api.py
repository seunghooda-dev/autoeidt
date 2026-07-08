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
                "render_warnings": ["Shorts 02: 렌더 파일 크기가 매우 작습니다."],
                "batch_render_items": [
                    {
                        "label": "Shorts 01",
                        "path": "C:/AutoEdit/outputs/shorts_01.mp4",
                        "url": "/api/jobs/rendered-job/download/shorts_01.mp4",
                        "output_name": "shorts_01.mp4",
                        "duration_seconds": 45.5,
                        "size_bytes": 123456,
                        "warnings": [],
                        "segments": [],
                    },
                    {
                        "label": "Shorts 02",
                        "path": "C:/AutoEdit/outputs/shorts_02.mp4",
                        "url": "/api/jobs/rendered-job/download/shorts_02.mp4",
                        "output_name": "shorts_02.mp4",
                        "duration_seconds": 61.2,
                        "size_bytes": 234567,
                        "warnings": ["렌더 파일 크기가 매우 작습니다."],
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
    assert payload["render_warnings"] == ["Shorts 02: 렌더 파일 크기가 매우 작습니다."]
    assert len(payload["batch_render_items"]) == 2
    assert payload["batch_render_items"][1]["path"].endswith("shorts_02.mp4")
    assert payload["batch_render_items"][1]["duration_seconds"] == 61.2
    assert payload["batch_render_items"][1]["size_bytes"] == 234567
    assert payload["batch_render_items"][1]["warnings"] == [
        "렌더 파일 크기가 매우 작습니다."
    ]


def test_project_endpoints_preserve_render_settings(monkeypatch) -> None:
    class FakeStore:
        def __init__(self) -> None:
            self.data = {
                "job_id": "job-1",
                "status": "completed",
                "stage": "completed",
                "progress": 100,
                "message": "done",
                "original_filename": "source.mp4",
            }

        def load(self, job_id: str) -> dict:
            assert job_id == "job-1"
            return dict(self.data)

        def update(self, job_id: str, **fields) -> dict:
            assert job_id == "job-1"
            self.data.update(fields)
            return dict(self.data)

    monkeypatch.setattr(jobs, "store", FakeStore())

    response = client.post(
        "/api/jobs/job-1/project",
        json={
            "name": "Shorts Project",
            "duration": 120,
            "segments": [],
            "captions": [],
            "waveform": [],
            "timeline_markers": [
                {
                    "id": 1,
                    "seconds": 22.0,
                    "label": "Hook",
                    "color": "cyan",
                    "note": "opening marker",
                }
            ],
            "include_captions": False,
            "caption_style_preset": "shorts",
            "export_aspect_ratio": "9:16",
            "mark_in": 12.5,
            "mark_out": 58.0,
            "shorts_candidates": [
                {
                    "id": 2,
                    "label": "News 02",
                    "reason": "strong news hook",
                    "segments": [],
                    "quality_score": 82.5,
                    "selected": True,
                }
            ],
            "selected_shorts_id": 2,
        },
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["include_captions"] is False
    assert payload["caption_style_preset"] == "shorts"
    assert payload["export_aspect_ratio"] == "9:16"
    assert payload["mark_in"] == 12.5
    assert payload["mark_out"] == 58.0
    assert payload["timeline_markers"][0]["label"] == "Hook"
    assert payload["timeline_markers"][0]["seconds"] == 22.0
    assert payload["shorts_candidates"][0]["label"] == "News 02"
    assert payload["selected_shorts_id"] == 2

    get_response = client.get("/api/jobs/job-1/project")

    assert get_response.status_code == 200
    get_payload = get_response.json()
    assert get_payload["include_captions"] is False
    assert get_payload["caption_style_preset"] == "shorts"
    assert get_payload["export_aspect_ratio"] == "9:16"
    assert get_payload["timeline_markers"][0]["note"] == "opening marker"
    assert get_payload["shorts_candidates"][0]["quality_score"] == 82.5
    assert get_payload["selected_shorts_id"] == 2
