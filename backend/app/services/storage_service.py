import json
import os
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any, Iterator


TERMINAL_JOB_STATUSES = {"completed", "rendered", "cancelled", "failed"}


def _iter_regular_files(root: Path) -> Iterator[tuple[Path, os.stat_result]]:
    if not root.exists() or not root.is_dir():
        return
    for current, directories, filenames in os.walk(root, followlinks=False):
        current_path = Path(current)
        directories[:] = [
            name for name in directories if not (current_path / name).is_symlink()
        ]
        for filename in filenames:
            path = current_path / filename
            try:
                if path.is_symlink() or not path.is_file():
                    continue
                yield path, path.stat()
            except OSError:
                continue


def _category_for(relative: Path) -> str:
    parts = relative.parts
    if parts and parts[0] == "preview_proxies":
        return "preview_cache"
    if len(parts) >= 3 and parts[0] == "jobs":
        if parts[2] == "work":
            return "analysis_cache"
        if parts[2] == "uploads":
            return "source_copies"
        if parts[2] == "outputs":
            return "render_outputs"
    return "metadata"


def _category_payloads() -> dict[str, dict[str, Any]]:
    return {
        "preview_cache": {
            "key": "preview_cache",
            "label": "Preview cache",
            "bytes": 0,
            "files": 0,
            "reclaimable_bytes": 0,
            "protected": False,
        },
        "analysis_cache": {
            "key": "analysis_cache",
            "label": "Analysis cache",
            "bytes": 0,
            "files": 0,
            "reclaimable_bytes": 0,
            "protected": False,
        },
        "source_copies": {
            "key": "source_copies",
            "label": "Imported sources",
            "bytes": 0,
            "files": 0,
            "reclaimable_bytes": 0,
            "protected": True,
        },
        "render_outputs": {
            "key": "render_outputs",
            "label": "Render outputs",
            "bytes": 0,
            "files": 0,
            "reclaimable_bytes": 0,
            "protected": True,
        },
        "metadata": {
            "key": "metadata",
            "label": "Projects and profiles",
            "bytes": 0,
            "files": 0,
            "reclaimable_bytes": 0,
            "protected": True,
        },
    }


def _parse_datetime(value: Any) -> datetime | None:
    if not value:
        return None
    try:
        parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=UTC)
    return parsed.astimezone(UTC)


def _load_job_cleanup_state(job_dir: Path) -> tuple[str, datetime | None]:
    job_file = job_dir / "job.json"
    try:
        payload = json.loads(job_file.read_text(encoding="utf-8"))
        status = str(payload.get("status") or "").lower()
        updated_at = _parse_datetime(payload.get("updated_at"))
        if updated_at is None:
            updated_at = datetime.fromtimestamp(job_file.stat().st_mtime, UTC)
        return status, updated_at
    except (OSError, json.JSONDecodeError, TypeError):
        return "", None


def _eligible_work_directories(
    data_dir: Path,
    *,
    active_job_id: str | None,
    cutoff: datetime,
) -> set[Path]:
    jobs_dir = data_dir / "jobs"
    eligible: set[Path] = set()
    if not jobs_dir.exists():
        return eligible
    for job_dir in jobs_dir.iterdir():
        try:
            if (
                not job_dir.is_dir()
                or job_dir.is_symlink()
                or job_dir.name == active_job_id
            ):
                continue
        except OSError:
            continue
        status, updated_at = _load_job_cleanup_state(job_dir)
        if (
            status in TERMINAL_JOB_STATUSES
            and updated_at is not None
            and updated_at <= cutoff
        ):
            eligible.add(job_dir / "work")
    return eligible


def _is_within(path: Path, root: Path) -> bool:
    try:
        path.resolve(strict=False).relative_to(root.resolve(strict=True))
        return True
    except (OSError, ValueError):
        return False


def collect_storage_usage(
    data_dir: Path,
    *,
    active_job_id: str | None = None,
    retention_hours: int = 24,
    now: datetime | None = None,
) -> dict[str, Any]:
    root = data_dir.resolve(strict=False)
    current = (now or datetime.now(UTC)).astimezone(UTC)
    cutoff = current - timedelta(hours=max(1, retention_hours))
    eligible_work = _eligible_work_directories(
        root,
        active_job_id=active_job_id,
        cutoff=cutoff,
    )
    categories = _category_payloads()
    total_bytes = 0

    for path, stat in _iter_regular_files(root):
        try:
            relative = path.relative_to(root)
        except ValueError:
            continue
        key = _category_for(relative)
        size = max(0, int(stat.st_size))
        categories[key]["bytes"] += size
        categories[key]["files"] += 1
        total_bytes += size
        if key == "preview_cache" and datetime.fromtimestamp(
            stat.st_mtime, UTC
        ) <= cutoff:
            categories[key]["reclaimable_bytes"] += size
        elif key == "analysis_cache" and any(
            _is_within(path, work_dir) for work_dir in eligible_work
        ):
            categories[key]["reclaimable_bytes"] += size

    reclaimable_bytes = sum(
        int(category["reclaimable_bytes"]) for category in categories.values()
    )
    return {
        "data_dir": str(root),
        "total_bytes": total_bytes,
        "reclaimable_bytes": reclaimable_bytes,
        "retention_hours": max(1, retention_hours),
        "categories": list(categories.values()),
        "protected_items": [
            "Imported source copies",
            "Render outputs",
            "Project metadata",
            "Current and running jobs",
        ],
    }


def _remove_empty_directories(root: Path) -> None:
    if not root.exists() or not root.is_dir() or root.is_symlink():
        return
    for current, directories, _ in os.walk(root, topdown=False, followlinks=False):
        current_path = Path(current)
        for directory in directories:
            path = current_path / directory
            try:
                if not path.is_symlink() and not any(path.iterdir()):
                    path.rmdir()
            except OSError:
                continue


def cleanup_safe_storage(
    data_dir: Path,
    *,
    active_job_id: str | None = None,
    retention_hours: int = 24,
    now: datetime | None = None,
) -> dict[str, Any]:
    root = data_dir.resolve(strict=False)
    current = (now or datetime.now(UTC)).astimezone(UTC)
    cutoff = current - timedelta(hours=max(1, retention_hours))
    before = collect_storage_usage(
        root,
        active_job_id=active_job_id,
        retention_hours=retention_hours,
        now=current,
    )
    eligible_work = _eligible_work_directories(
        root,
        active_job_id=active_job_id,
        cutoff=cutoff,
    )
    candidates: list[Path] = []

    for path, stat in _iter_regular_files(root / "preview_proxies"):
        if datetime.fromtimestamp(stat.st_mtime, UTC) <= cutoff:
            candidates.append(path)
    for work_dir in eligible_work:
        candidates.extend(path for path, _ in _iter_regular_files(work_dir))

    deleted_files = 0
    skipped_files = 0
    freed_bytes = 0
    seen: set[Path] = set()
    for path in candidates:
        normalized = path.resolve(strict=False)
        if normalized in seen or not _is_within(normalized, root):
            continue
        seen.add(normalized)
        try:
            if path.is_symlink() or not path.is_file():
                skipped_files += 1
                continue
            size = max(0, path.stat().st_size)
            path.unlink()
            deleted_files += 1
            freed_bytes += size
        except OSError:
            skipped_files += 1

    _remove_empty_directories(root / "preview_proxies")
    for work_dir in eligible_work:
        _remove_empty_directories(work_dir)

    after = collect_storage_usage(
        root,
        active_job_id=active_job_id,
        retention_hours=retention_hours,
        now=current,
    )
    return {
        "freed_bytes": freed_bytes,
        "deleted_files": deleted_files,
        "skipped_files": skipped_files,
        "before": before,
        "after": after,
    }
