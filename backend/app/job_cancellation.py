from contextvars import ContextVar, Token
from typing import Any

from app.storage import store


class JobCancelledError(RuntimeError):
    pass


_active_job_id: ContextVar[str | None] = ContextVar(
    "autoedit_active_job_id",
    default=None,
)


def activate_job_cancellation(job_id: str) -> Token[str | None]:
    return _active_job_id.set(job_id)


def deactivate_job_cancellation(token: Token[str | None]) -> None:
    _active_job_id.reset(token)


def current_cancellable_job_id() -> str | None:
    return _active_job_id.get()


def job_cancellation_requested(job_id: str | None = None) -> bool:
    target = job_id or current_cancellable_job_id()
    if not target:
        return False
    try:
        job = store.load(target)
    except (FileNotFoundError, OSError, ValueError):
        return False
    return bool(job.get("cancel_requested")) or job.get("status") == "cancelled"


def raise_if_job_cancelled(job_id: str | None = None) -> None:
    target = job_id or current_cancellable_job_id()
    if target and job_cancellation_requested(target):
        raise JobCancelledError(f"job cancelled: {target}")


def mark_job_cancelled(
    job_id: str,
    *,
    message: str = "작업이 취소되었습니다",
    **fields: Any,
) -> dict[str, Any]:
    return store.update(
        job_id,
        status="cancelled",
        stage="cancelled",
        message=message,
        cancel_requested=False,
        error=None,
        **fields,
    )
