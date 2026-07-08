from fastapi.testclient import TestClient

from app.main import app


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
