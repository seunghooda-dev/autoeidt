from pathlib import Path
from typing import Any

from app import tasks


def test_unique_render_output_path_avoids_existing_and_forces_mp4(
    tmp_path: Path,
) -> None:
    (tmp_path / "shorts.mp4").write_text("existing", encoding="utf-8")

    output = tasks._unique_render_output_path(
        tmp_path,
        "shorts.mov",
        "shorts.mp4",
    )

    assert output.name == "shorts_002.mp4"


def test_unique_render_output_path_tracks_batch_reserved_names(
    tmp_path: Path,
) -> None:
    reserved: set[str] = set()

    first = tasks._unique_render_output_path(
        tmp_path,
        "duplicate.mp4",
        "shorts.mp4",
        reserved,
    )
    second = tasks._unique_render_output_path(
        tmp_path,
        "duplicate.mp4",
        "shorts.mp4",
        reserved,
    )

    assert first.name == "duplicate.mp4"
    assert second.name == "duplicate_002.mp4"


def test_render_video_job_does_not_overwrite_existing_output(
    tmp_path: Path,
    monkeypatch,
) -> None:
    class FakeStore:
        def __init__(self) -> None:
            self.output = tmp_path / "outputs"
            self.output.mkdir()
            self.data: dict[str, Any] = {
                "job_id": "job-1",
                "duration": 60,
                "video_path": str(tmp_path / "source.mp4"),
                "segments": [],
            }

        def load(self, job_id: str) -> dict[str, Any]:
            assert job_id == "job-1"
            return dict(self.data)

        def update(self, job_id: str, **fields: Any) -> dict[str, Any]:
            assert job_id == "job-1"
            self.data.update(fields)
            return dict(self.data)

        def output_dir(self, job_id: str) -> Path:
            assert job_id == "job-1"
            return self.output

    fake_store = FakeStore()
    (fake_store.output / "youtube_highlights.mp4").write_text(
        "previous",
        encoding="utf-8",
    )

    def fake_render_highlights(
        video_path: Path,
        segments: list[dict],
        output_path: Path,
        **kwargs,
    ) -> Path:
        output_path.write_text("new", encoding="utf-8")
        return output_path

    monkeypatch.setattr(tasks, "store", fake_store)
    monkeypatch.setattr(tasks, "render_highlights", fake_render_highlights)

    result = tasks.render_video_job(
        "job-1",
        [{"order": 1, "start": 0, "end": 10, "reason": "test"}],
        {"output_name": "youtube_highlights.mp4"},
    )

    assert Path(result["render_path"]).name == "youtube_highlights_002.mp4"
    assert result["render_duration_seconds"] == 10.0
    assert result["render_size_bytes"] == 3
    assert result["render_warnings"]
    assert "파일 크기" in result["render_warnings"][0]
    assert (fake_store.output / "youtube_highlights.mp4").read_text(
        encoding="utf-8",
    ) == "previous"
    assert (fake_store.output / "youtube_highlights_002.mp4").read_text(
        encoding="utf-8",
    ) == "new"


def test_batch_render_job_deduplicates_output_names(
    tmp_path: Path,
    monkeypatch,
) -> None:
    class FakeStore:
        def __init__(self) -> None:
            self.output = tmp_path / "outputs"
            self.output.mkdir()
            self.data: dict[str, Any] = {
                "job_id": "job-1",
                "duration": 120,
                "video_path": str(tmp_path / "source.mp4"),
            }

        def load(self, job_id: str) -> dict[str, Any]:
            assert job_id == "job-1"
            return dict(self.data)

        def update(self, job_id: str, **fields: Any) -> dict[str, Any]:
            assert job_id == "job-1"
            self.data.update(fields)
            return dict(self.data)

        def output_dir(self, job_id: str) -> Path:
            assert job_id == "job-1"
            return self.output

    fake_store = FakeStore()
    rendered_names: list[str] = []

    def fake_render_highlights(
        video_path: Path,
        segments: list[dict],
        output_path: Path,
        **kwargs,
    ) -> Path:
        rendered_names.append(output_path.name)
        output_path.write_text(output_path.name, encoding="utf-8")
        return output_path

    monkeypatch.setattr(tasks, "store", fake_store)
    monkeypatch.setattr(tasks, "render_highlights", fake_render_highlights)

    result = tasks.render_batch_video_job(
        "job-1",
        [
            {
                "label": "Shorts 01",
                "output_name": "shorts.mp4",
                "segments": [{"order": 1, "start": 0, "end": 10, "reason": "a"}],
            },
            {
                "label": "Shorts 02",
                "output_name": "shorts.mp4",
                "segments": [
                    {
                        "order": 1,
                        "start": 20,
                        "end": 30,
                        "reason": "b",
                        "playback_speed": 2,
                    }
                ],
            },
        ],
        {},
    )

    assert rendered_names == ["shorts.mp4", "shorts_002.mp4"]
    assert [
        item["output_name"] for item in result["batch_render_items"]
    ] == rendered_names
    assert result["batch_render_items"][0]["duration_seconds"] == 10.0
    assert result["batch_render_items"][1]["duration_seconds"] == 5.0
    assert result["batch_render_items"][0]["size_bytes"] == len("shorts.mp4")
    assert result["batch_render_items"][0]["warnings"]
    assert result["render_warnings"]
