from fastapi.testclient import TestClient

from app.main import app


client = TestClient(app)


def test_style_train_requires_reference_input() -> None:
    response = client.post("/api/styles/train", data={"name": "Empty"})

    assert response.status_code == 400


def test_style_lookup_returns_not_found_for_unknown_profile() -> None:
    response = client.get("/api/styles/missing")

    assert response.status_code == 404
