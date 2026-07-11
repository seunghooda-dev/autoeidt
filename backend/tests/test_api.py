from pathlib import Path

from fastapi.testclient import TestClient

from app.main import app
from app.routers import jobs


client = TestClient(app)


def test_health_endpoint() -> None:
    response = client.get("/health")

    assert response.status_code == 200
    payload = response.json()
    assert payload["status"] == "ok"
    assert payload["timeline_frame_rate"] == "30"
    assert payload["preview_proxy_seconds"] == 8
    assert "preview_audio_mix_v1" in payload["features"]
    assert "broadcast_audio_a1_a2_v2" in payload["features"]
    assert "fast_proxy_preview_v2" in payload["features"]
    assert "fast_proxy_preview_v3" in payload["features"]
    assert "preview_reconnect_v1" in payload["features"]
    assert "compatibility_preview_v1" in payload["features"]
    assert "local_preview_file_v1" in payload["features"]
    assert "safe_storage_cleanup_v1" in payload["features"]
    assert "cancellable_jobs_v1" in payload["features"]
    assert "recent_jobs_v1" in payload["features"]
    assert "timeline_30p_ndf" in payload["features"]
    assert "timeline_thumbnails_v1" in payload["features"]
    assert "standalone_audio_clips_v1" in payload["features"]
    assert "per_track_controls_v1" in payload["features"]
    assert "audio_track_solo_v1" in payload["features"]
    assert "lossless_multitrack_project_v1" in payload["features"]
    assert "audio_gain_keyframes_v1" in payload["features"]
    assert "broadcast_graphics_g1_v1" in payload["features"]


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


def test_local_thumbnail_returns_not_found_for_missing_file() -> None:
    response = client.post(
        "/api/jobs/thumbnail-local",
        json={"path": "C:/definitely/missing/source.mxf", "time_seconds": 4.0},
    )

    assert response.status_code == 404


def test_cancel_active_job_is_idempotent_and_preserves_existing_results(
    monkeypatch,
) -> None:
    class FakeStore:
        def __init__(self) -> None:
            self.job = {
                "job_id": "active-job",
                "status": "processing",
                "stage": "transcribing",
                "progress": 45,
                "message": "working",
                "render_path": "C:/outputs/previous.mp4",
                "render_url": "/api/jobs/active-job/download",
                "segments": [],
            }

        def load(self, job_id: str) -> dict:
            assert job_id == "active-job"
            return dict(self.job)

        def update(self, job_id: str, **fields) -> dict:
            assert job_id == "active-job"
            self.job.update(fields)
            return dict(self.job)

    fake_store = FakeStore()
    monkeypatch.setattr(jobs, "store", fake_store)

    response = client.post("/api/jobs/active-job/cancel")
    repeated = client.post("/api/jobs/active-job/cancel")

    assert response.status_code == 200
    assert repeated.status_code == 200
    payload = repeated.json()
    assert payload["status"] == "cancelled"
    assert payload["stage"] == "cancelled"
    assert payload["render_path"] == "C:/outputs/previous.mp4"
    assert payload["error"] is None


def test_cancel_rejects_finished_job(monkeypatch) -> None:
    class FakeStore:
        def load(self, job_id: str) -> dict:
            return {
                "job_id": job_id,
                "status": "rendered",
                "stage": "rendered",
                "progress": 100,
                "message": "done",
                "segments": [],
            }

    monkeypatch.setattr(jobs, "store", FakeStore())

    response = client.post("/api/jobs/finished-job/cancel")

    assert response.status_code == 409


def test_render_rejects_duplicate_request_while_job_is_active(monkeypatch) -> None:
    class FakeStore:
        def load(self, job_id: str) -> dict:
            return {
                "job_id": job_id,
                "status": "rendering",
                "stage": "rendering",
                "progress": 30,
                "message": "working",
                "segments": [],
            }

    monkeypatch.setattr(jobs, "store", FakeStore())

    response = client.post(
        "/api/jobs/active-render/render",
        json={
            "segments": [
                {"order": 1, "start": 0, "end": 5, "reason": "test"}
            ]
        },
    )

    assert response.status_code == 409
    assert response.json()["detail"] == "job is already active"


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
            "video_overlays": [
                {
                    "id": "v4-news",
                    "source_path": "C:/media/broll.mov",
                    "source_name": "broll.mov",
                    "timeline_start": 4,
                    "timeline_end": 9,
                    "source_start": 1,
                    "source_end": 6,
                    "audio_gain_keyframes": [
                        {"time": 0, "volume": 0.2},
                        {"time": 5, "volume": 1.1},
                    ],
                    "video_track": 4,
                    "audio_track": 8,
                }
            ],
            "audio_clips": [
                {
                    "id": "a7-bed",
                    "source_path": "C:/media/music.wav",
                    "source_name": "music.wav",
                    "timeline_start": 0,
                    "timeline_end": 20,
                    "source_start": 0,
                    "source_end": 20,
                    "gain_keyframes": [
                        {"time": 0, "volume": 0.5},
                        {"time": 20, "volume": 0.8},
                    ],
                    "track": 7,
                }
            ],
            "graphics": [
                {
                    "id": "g1-live",
                    "timeline_start": 1.019,
                    "timeline_end": 6.049,
                    "preset": "lower_third",
                    "headline": "Election update",
                    "subheadline": "Live from Seoul",
                    "position_x": 0.07,
                    "position_y": 0.81,
                    "accent_color": "#EF4444",
                }
            ],
            "graphics_track_locked": True,
            "graphics_track_visible": False,
            "active_video_track_count": 4,
            "active_audio_track_count": 8,
            "locked_video_tracks": [4],
            "hidden_video_tracks": [3],
            "locked_audio_tracks": [8],
            "muted_audio_tracks": [6],
            "solo_audio_tracks": [1, 7],
            "transcript": [
                {
                    "start": 12.5,
                    "end": 15.0,
                    "text": "보존할 STT 원문",
                }
            ],
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
            "selected_export_profiles": ["16:9", "9:16"],
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
    assert payload["selected_export_profiles"] == ["16:9", "9:16"]
    assert payload["transcript"][0]["text"] == "보존할 STT 원문"
    assert payload["mark_in"] == 12.5
    assert payload["mark_out"] == 58.0
    assert payload["timeline_markers"][0]["label"] == "Hook"
    assert payload["timeline_markers"][0]["seconds"] == 22.0
    assert payload["timeline_markers"][0]["enabled"] is False
    assert payload["shorts_candidates"][0]["label"] == "News 02"
    assert payload["selected_shorts_id"] == 2
    assert payload["video_overlays"][0]["id"] == "v4-news"
    assert payload["audio_clips"][0]["id"] == "a7-bed"
    assert payload["graphics"][0]["id"] == "g1-live"
    assert payload["graphics"][0]["timeline_start"] == 1.033333
    assert payload["graphics"][0]["accent_color"] == "#EF4444"
    assert payload["graphics_track_locked"] is True
    assert payload["graphics_track_visible"] is False
    assert payload["video_overlays"][0]["audio_gain_keyframes"][1]["volume"] == 1.1
    assert payload["audio_clips"][0]["gain_keyframes"][1]["time"] == 20.0
    assert payload["active_video_track_count"] == 4
    assert payload["active_audio_track_count"] == 8
    assert payload["locked_video_tracks"] == [4]
    assert payload["hidden_video_tracks"] == [3]
    assert payload["locked_audio_tracks"] == [8]
    assert payload["muted_audio_tracks"] == [6]
    assert payload["solo_audio_tracks"] == [1, 7]

    get_response = client.get("/api/jobs/job-1/project")

    assert get_response.status_code == 200
    get_payload = get_response.json()
    assert get_payload["original_path"] == str(source_path.resolve())
    assert get_payload["timeline_frame_rate"] == 30.0
    assert get_payload["timeline_timecode_mode"] == "non_drop"
    assert get_payload["include_captions"] is False
    assert get_payload["caption_style_preset"] == "shorts"
    assert get_payload["export_aspect_ratio"] == "9:16"
    assert get_payload["selected_export_profiles"] == ["16:9", "9:16"]
    assert get_payload["transcript"][0]["start"] == 12.5
    assert get_payload["timeline_markers"][0]["note"] == "opening marker"
    assert get_payload["timeline_markers"][0]["enabled"] is False
    assert get_payload["shorts_candidates"][0]["quality_score"] == 82.5
    assert get_payload["selected_shorts_id"] == 2
    assert get_payload["video_overlays"][0]["video_track"] == 4
    assert get_payload["video_overlays"][0]["audio_track"] == 8
    assert get_payload["audio_clips"][0]["track"] == 7
    assert get_payload["graphics"][0]["headline"] == "Election update"
    assert get_payload["graphics_track_locked"] is True
    assert get_payload["graphics_track_visible"] is False
    assert get_payload["video_overlays"][0]["audio_gain_keyframes"][0]["volume"] == 0.2
    assert get_payload["audio_clips"][0]["gain_keyframes"][0]["volume"] == 0.5
    assert get_payload["active_video_track_count"] == 4
    assert get_payload["active_audio_track_count"] == 8
    assert get_payload["locked_video_tracks"] == [4]
    assert get_payload["hidden_video_tracks"] == [3]
    assert get_payload["locked_audio_tracks"] == [8]
    assert get_payload["muted_audio_tracks"] == [6]
    assert get_payload["solo_audio_tracks"] == [1, 7]

    legacy_response = client.post(
        "/api/jobs/job-1/project",
        json={
            "name": "Legacy Project Save",
            "duration": 120,
            "segments": [],
            "captions": [],
            "waveform": [],
            "export_aspect_ratio": "1:1",
        },
    )

    assert legacy_response.status_code == 200
    legacy_payload = legacy_response.json()
    assert legacy_payload["transcript"][0]["text"] == "보존할 STT 원문"
    assert legacy_payload["selected_export_profiles"] == ["1:1"]
