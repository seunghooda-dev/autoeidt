from enum import StrEnum
from typing import Any

from pydantic import BaseModel, Field, field_validator


class JobStatus(StrEnum):
    queued = "queued"
    processing = "processing"
    completed = "completed"
    rendering = "rendering"
    rendered = "rendered"
    failed = "failed"


class TranscriptWord(BaseModel):
    start: float
    end: float
    word: str


class TranscriptSegment(BaseModel):
    start: float
    end: float
    text: str
    words: list[TranscriptWord] = Field(default_factory=list)


class HighlightSegment(BaseModel):
    order: int = 0
    start: float
    end: float
    reason: str
    script: str = ""
    source: str = "ai"

    @field_validator("end")
    @classmethod
    def end_must_be_after_start(cls, value: float, info: Any) -> float:
        start = info.data.get("start")
        if start is not None and value <= start:
            raise ValueError("end must be greater than start")
        return value


class UploadJobResponse(BaseModel):
    job_id: str
    status: JobStatus
    stage: str
    progress: int
    duration: float | None = None


class JobStatusResponse(BaseModel):
    job_id: str
    status: JobStatus
    stage: str
    progress: int
    message: str = ""
    duration: float | None = None
    original_filename: str | None = None
    segments: list[HighlightSegment] = Field(default_factory=list)
    render_url: str | None = None
    error: str | None = None


class TimelineResponse(BaseModel):
    job_id: str
    duration: float
    segments: list[HighlightSegment]
    transcript: list[TranscriptSegment] = Field(default_factory=list)


class RenderRequest(BaseModel):
    segments: list[HighlightSegment]


class RenderResponse(BaseModel):
    job_id: str
    render_task_id: str
    status: JobStatus
    stage: str
