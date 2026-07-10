import sys
import threading
import time
from pathlib import Path
from typing import Any

import pytest

from app import job_cancellation
from app.job_cancellation import (
    JobCancelledError,
    activate_job_cancellation,
    deactivate_job_cancellation,
)
from app.services import ffmpeg_service
from app import tasks


class _MemoryJobStore:
    def __init__(self, root: Path, job: dict[str, Any]) -> None:
        self.root = root
        self.job = dict(job)
        self.lock = threading.Lock()

    def load(self, job_id: str) -> dict[str, Any]:
        assert job_id == self.job["job_id"]
        with self.lock:
            return dict(self.job)

    def update(self, job_id: str, **fields: Any) -> dict[str, Any]:
        assert job_id == self.job["job_id"]
        with self.lock:
            self.job.update(fields)
            return dict(self.job)

    def work_dir(self, job_id: str) -> Path:
        path = self.root / "jobs" / job_id / "work"
        path.mkdir(parents=True, exist_ok=True)
        return path

    def output_dir(self, job_id: str) -> Path:
        path = self.root / "jobs" / job_id / "outputs"
        path.mkdir(parents=True, exist_ok=True)
        return path


def _job(job_id: str = "cancel-job") -> dict[str, Any]:
    return {
        "job_id": job_id,
        "status": "completed",
        "stage": "completed",
        "progress": 100,
        "message": "ready",
        "video_path": "C:/media/source.mxf",
        "duration": 60.0,
        "segments": [],
        "cancel_requested": False,
        "error": None,
    }


def test_cancellable_subprocess_terminates_promptly(
    tmp_path: Path,
    monkeypatch,
) -> None:
    store = _MemoryJobStore(tmp_path, _job())
    monkeypatch.setattr(job_cancellation, "store", store)
    timer = threading.Timer(
        0.3,
        lambda: store.update(
            "cancel-job",
            status="cancelled",
            cancel_requested=True,
        ),
    )
    token = activate_job_cancellation("cancel-job")
    started = time.monotonic()
    timer.start()
    try:
        with pytest.raises(JobCancelledError):
            ffmpeg_service._run(
                [sys.executable, "-c", "import time; time.sleep(10)"],
            )
    finally:
        timer.cancel()
        deactivate_job_cancellation(token)

    assert time.monotonic() - started < 3


def test_analysis_cancellation_stops_before_next_stage(
    tmp_path: Path,
    monkeypatch,
) -> None:
    store = _MemoryJobStore(tmp_path, _job())
    monkeypatch.setattr(tasks, "store", store)
    monkeypatch.setattr(job_cancellation, "store", store)
    extract_called = False

    def cancel_after_probe(_path: Path) -> float:
        partial_audio = store.work_dir("cancel-job") / "audio.wav"
        partial_audio.write_bytes(b"partial")
        store.update("cancel-job", status="cancelled", cancel_requested=True)
        return 60.0

    def unexpected_extract(_video: Path, _audio: Path) -> Path:
        nonlocal extract_called
        extract_called = True
        return _audio

    monkeypatch.setattr(tasks, "probe_duration", cancel_after_probe)
    monkeypatch.setattr(tasks, "extract_audio", unexpected_extract)

    result = tasks.analyze_video_job("cancel-job")

    assert extract_called is False
    assert result["status"] == "cancelled"
    assert result["stage"] == "cancelled"
    assert result["cancel_requested"] is False
    assert result["error"] is None
    assert not (store.work_dir("cancel-job") / "audio.wav").exists()


def test_cancelled_rerender_removes_partial_but_preserves_previous_output(
    tmp_path: Path,
    monkeypatch,
) -> None:
    previous_output = tmp_path / "previous.mp4"
    previous_output.write_bytes(b"finished")
    job = _job()
    job.update(
        {
            "render_path": str(previous_output),
            "render_url": "/api/jobs/cancel-job/download",
        }
    )
    store = _MemoryJobStore(tmp_path, job)
    monkeypatch.setattr(tasks, "store", store)
    monkeypatch.setattr(job_cancellation, "store", store)
    partial_path: Path | None = None

    def cancelled_render(
        _video_path: Path,
        _segments: list[dict[str, Any]],
        output_path: Path,
        **_kwargs: Any,
    ) -> Path:
        nonlocal partial_path
        partial_path = output_path
        output_path.write_bytes(b"partial")
        store.update("cancel-job", status="cancelled", cancel_requested=True)
        raise RuntimeError("encoder stopped during cancellation")

    monkeypatch.setattr(tasks, "render_highlights", cancelled_render)

    result = tasks.render_video_job(
        "cancel-job",
        [{"order": 1, "start": 0, "end": 5, "reason": "test"}],
        {"output_name": "new-render.mp4"},
    )

    assert result["status"] == "cancelled"
    assert result["render_path"] == str(previous_output)
    assert previous_output.read_bytes() == b"finished"
    assert partial_path is not None
    assert not partial_path.exists()
