from pathlib import Path

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
                "render_manifest_items": [
                    {
                        "label": "Render Manifest JSON",
                        "path": "C:/AutoEdit/outputs/render_manifest.json",
                        "url": "/api/jobs/rendered-job/download/render_manifest.json",
                        "output_name": "render_manifest.json",
                        "kind": "manifest",
                        "duration_seconds": 0,
                        "size_bytes": 2048,
                        "warnings": [],
                        "segments": [],
                    }
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
    assert payload["render_manifest_items"][0]["kind"] == "manifest"
    assert payload["render_manifest_items"][0]["output_name"] == (
        "render_manifest.json"
    )


def test_download_named_render_serves_manifest_media_types(
    monkeypatch,
    tmp_path: Path,
) -> None:
    output_dir = tmp_path / "outputs"
    output_dir.mkdir()
    (output_dir / "render_manifest.json").write_text("{}", encoding="utf-8")
    (output_dir / "render_manifest.csv").write_text("a,b\n", encoding="utf-8")

    class FakeStore:
        def load(self, job_id: str) -> dict:
            assert job_id == "rendered-job"
            return {
                "job_id": job_id,
                "status": "rendered",
                "stage": "batch_rendered",
                "progress": 100,
                "message": "done",
            }

        def output_dir(self, job_id: str) -> Path:
            assert job_id == "rendered-job"
            return output_dir

    monkeypatch.setattr(jobs, "store", FakeStore())

    json_response = client.get(
        "/api/jobs/rendered-job/download/render_manifest.json"
    )
    csv_response = client.get("/api/jobs/rendered-job/download/render_manifest.csv")

    assert json_response.status_code == 200
    assert json_response.headers["content-type"].startswith("application/json")
    assert csv_response.status_code == 200
    assert csv_response.headers["content-type"].startswith("text/csv")


def test_project_endpoints_preserve_render_settings(
    monkeypatch,
    tmp_path: Path,
) -> None:
    source_path = tmp_path / "relinked_source.mxf"
    source_path.write_bytes(b"fake media")

    class FakeStore:
        def __init__(self) -> None:
            self.data = {
                "job_id": "job-1",
                "status": "completed",
                "stage": "completed",
                "progress": 100,
                "message": "done",
                "original_filename": "source.mp4",
                "video_path": "C:/old/source.mp4",
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
            "original_path": str(source_path),
            "duration": 120,
            "timeline_frame_rate": 29.97,
            "timeline_timecode_mode": "drop",
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
                    "enabled": False,
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
    assert payload["original_filename"] == "relinked_source.mxf"
    assert payload["original_path"] == str(source_path.resolve())
    assert payload["timeline_frame_rate"] == 30.0
    assert payload["timeline_timecode_mode"] == "non_drop"
    assert payload["include_captions"] is False
    assert payload["caption_style_preset"] == "shorts"
    assert payload["export_aspect_ratio"] == "9:16"
    assert payload["mark_in"] == 12.5
    assert payload["mark_out"] == 58.0
    assert payload["timeline_markers"][0]["label"] == "Hook"
    assert payload["timeline_markers"][0]["seconds"] == 22.0
    assert payload["timeline_markers"][0]["enabled"] is False
    assert payload["shorts_candidates"][0]["label"] == "News 02"
    assert payload["selected_shorts_id"] == 2

    get_response = client.get("/api/jobs/job-1/project")

    assert get_response.status_code == 200
    get_payload = get_response.json()
    assert get_payload["original_path"] == str(source_path.resolve())
    assert get_payload["timeline_frame_rate"] == 30.0
    assert get_payload["timeline_timecode_mode"] == "non_drop"
    assert get_payload["include_captions"] is False
    assert get_payload["caption_style_preset"] == "shorts"
    assert get_payload["export_aspect_ratio"] == "9:16"
    assert get_payload["timeline_markers"][0]["note"] == "opening marker"
    assert get_payload["timeline_markers"][0]["enabled"] is False
    assert get_payload["shorts_candidates"][0]["quality_score"] == 82.5
    assert get_payload["selected_shorts_id"] == 2
