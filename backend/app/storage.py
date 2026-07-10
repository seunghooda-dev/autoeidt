import json
import os
import re
import uuid
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from app.config import get_settings
from app.schemas import JobStatus


def now_iso() -> str:
    return datetime.now(UTC).isoformat()


def safe_filename(filename: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9._-]+", "_", filename).strip("._")
    return cleaned or "video.mp4"


class JobStore:
    def __init__(self, root: Path | None = None) -> None:
        settings = get_settings()
        self.root = root or settings.data_dir
        self.jobs_dir = self.root / "jobs"
        self.styles_dir = self.root / "styles"
        self.jobs_dir.mkdir(parents=True, exist_ok=True)
        self.styles_dir.mkdir(parents=True, exist_ok=True)

    def create_job(self, original_filename: str, video_path: Path) -> dict[str, Any]:
        job_id = uuid.uuid4().hex
        data = {
            "job_id": job_id,
            "status": JobStatus.queued.value,
            "stage": "queued",
            "progress": 0,
            "message": "작업 대기 중",
            "original_filename": original_filename,
            "video_path": str(video_path),
            "audio_path": None,
            "duration": None,
            "transcript": [],
            "segments": [],
            "render_path": None,
            "render_url": None,
            "error": None,
            "created_at": now_iso(),
            "updated_at": now_iso(),
        }
        return self.save(job_id, data)

    def job_dir(self, job_id: str) -> Path:
        return self.jobs_dir / job_id

    def upload_dir(self, job_id: str) -> Path:
        path = self.job_dir(job_id) / "uploads"
        path.mkdir(parents=True, exist_ok=True)
        return path

    def work_dir(self, job_id: str) -> Path:
        path = self.job_dir(job_id) / "work"
        path.mkdir(parents=True, exist_ok=True)
        return path

    def output_dir(self, job_id: str) -> Path:
        path = self.job_dir(job_id) / "outputs"
        path.mkdir(parents=True, exist_ok=True)
        return path

    def job_file(self, job_id: str) -> Path:
        return self.job_dir(job_id) / "job.json"

    def style_dir(self, style_id: str) -> Path:
        return self.styles_dir / style_id

    def style_upload_dir(self, style_id: str) -> Path:
        path = self.style_dir(style_id) / "references"
        path.mkdir(parents=True, exist_ok=True)
        return path

    def style_work_dir(self, style_id: str) -> Path:
        path = self.style_dir(style_id) / "work"
        path.mkdir(parents=True, exist_ok=True)
        return path

    def style_file(self, style_id: str) -> Path:
        return self.style_dir(style_id) / "style.json"

    def load(self, job_id: str) -> dict[str, Any]:
        path = self.job_file(job_id)
        if not path.exists():
            raise FileNotFoundError(f"job not found: {job_id}")
        return json.loads(path.read_text(encoding="utf-8"))

    def save(self, job_id: str, data: dict[str, Any]) -> dict[str, Any]:
        data["updated_at"] = now_iso()
        path = self.job_file(job_id)
        path.parent.mkdir(parents=True, exist_ok=True)
        temp_path = path.with_suffix(f".{uuid.uuid4().hex}.tmp")
        temp_path.write_text(
            json.dumps(data, ensure_ascii=False, indent=2, default=str),
            encoding="utf-8",
        )
        os.replace(temp_path, path)
        return data

    def update(self, job_id: str, **fields: Any) -> dict[str, Any]:
        data = self.load(job_id)
        data.update(fields)
        return self.save(job_id, data)

    def list_jobs(self, limit: int | None = 50) -> list[dict[str, Any]]:
        jobs: list[dict[str, Any]] = []
        for path in self.jobs_dir.glob("*/job.json"):
            try:
                payload = json.loads(path.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError, TypeError):
                continue
            if isinstance(payload, dict) and payload.get("job_id"):
                jobs.append(payload)
        jobs.sort(key=lambda item: str(item.get("updated_at") or ""), reverse=True)
        if limit is None:
            return jobs
        return jobs[: max(0, limit)]

    def recover_interrupted_jobs(self) -> int:
        active_statuses = {
            JobStatus.queued.value,
            JobStatus.processing.value,
            JobStatus.rendering.value,
        }
        recovered = 0
        for job in self.list_jobs(limit=None):
            if str(job.get("status") or "") not in active_statuses:
                continue
            self.update(
                str(job["job_id"]),
                status=JobStatus.cancelled.value,
                stage="interrupted",
                message="이전 엔진 세션이 종료되어 작업이 중단되었습니다",
                cancel_requested=False,
                error=None,
            )
            recovered += 1
        return recovered

    def load_style(self, style_id: str) -> dict[str, Any]:
        path = self.style_file(style_id)
        if not path.exists():
            raise FileNotFoundError(f"style profile not found: {style_id}")
        return json.loads(path.read_text(encoding="utf-8"))

    def save_style(self, style_id: str, data: dict[str, Any]) -> dict[str, Any]:
        data["updated_at"] = now_iso()
        path = self.style_file(style_id)
        path.parent.mkdir(parents=True, exist_ok=True)
        temp_path = path.with_suffix(f".{uuid.uuid4().hex}.tmp")
        temp_path.write_text(
            json.dumps(data, ensure_ascii=False, indent=2, default=str),
            encoding="utf-8",
        )
        os.replace(temp_path, path)
        return data

    def update_style(self, style_id: str, **fields: Any) -> dict[str, Any]:
        data = self.load_style(style_id)
        data.update(fields)
        return self.save_style(style_id, data)

    def list_styles(self) -> list[dict[str, Any]]:
        styles: list[dict[str, Any]] = []
        for path in sorted(self.styles_dir.glob("*/style.json")):
            try:
                styles.append(json.loads(path.read_text(encoding="utf-8")))
            except Exception:
                continue
        styles.sort(key=lambda item: str(item.get("updated_at", "")), reverse=True)
        return styles


store = JobStore()
