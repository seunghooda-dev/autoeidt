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
