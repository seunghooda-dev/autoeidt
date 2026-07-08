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


class CaptionSegment(BaseModel):
    order: int = 0
    start: float
    end: float
    text: str
    enabled: bool = True


class HighlightSegment(BaseModel):
    order: int = 0
    start: float
    end: float
    reason: str
    script: str = ""
    source: str = "ai"
    video_enabled: bool = True
    video_fade_in: float = 0.0
    video_fade_out: float = 0.0
    color_brightness: float = 0.0
    color_contrast: float = 1.0
    color_saturation: float = 1.0
    audio_start: float | None = None
    audio_end: float | None = None
    audio_muted: bool = False
    audio_volume: float = 1.0
    audio_pan: float = 0.0
    audio_normalize: bool = False
    audio_linked: bool = True
    playback_speed: float = 1.0
    audio_fade_in: float = 0.0
    audio_fade_out: float = 0.0
    score: float = 0.0
    tags: list[str] = Field(default_factory=list)

    @field_validator("end")
    @classmethod
    def end_must_be_after_start(cls, value: float, info: Any) -> float:
        start = info.data.get("start")
        if start is not None and value <= start:
            raise ValueError("end must be greater than start")
        return value

    @field_validator("audio_volume")
    @classmethod
    def audio_volume_must_be_safe(cls, value: float) -> float:
        return max(0.0, min(float(value), 2.0))

    @field_validator("audio_pan")
    @classmethod
    def audio_pan_must_be_safe(cls, value: float) -> float:
        return max(-1.0, min(float(value), 1.0))

    @field_validator("playback_speed")
    @classmethod
    def playback_speed_must_be_safe(cls, value: float) -> float:
        return max(0.25, min(float(value), 4.0))

    @field_validator(
        "audio_fade_in",
        "audio_fade_out",
        "video_fade_in",
        "video_fade_out",
    )
    @classmethod
    def audio_fade_must_be_safe(cls, value: float) -> float:
        return max(0.0, min(float(value), 10.0))

    @field_validator("color_brightness")
    @classmethod
    def color_brightness_must_be_safe(cls, value: float) -> float:
        return max(-0.3, min(float(value), 0.3))

    @field_validator("color_contrast")
    @classmethod
    def color_contrast_must_be_safe(cls, value: float) -> float:
        return max(0.5, min(float(value), 1.8))

    @field_validator("color_saturation")
    @classmethod
    def color_saturation_must_be_safe(cls, value: float) -> float:
        return max(0.0, min(float(value), 2.0))

    @field_validator("score")
    @classmethod
    def score_must_be_safe(cls, value: float) -> float:
        return max(0.0, min(float(value), 20.0))


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
    captions: list[CaptionSegment] = Field(default_factory=list)
    waveform: list[float] = Field(default_factory=list)


class RenderRequest(BaseModel):
    segments: list[HighlightSegment]
    captions: list[CaptionSegment] = Field(default_factory=list)
    aspect_ratio: str = "16:9"
    include_captions: bool = False
    output_name: str = "youtube_highlights.mp4"


class RenderResponse(BaseModel):
    job_id: str
    render_task_id: str
    status: JobStatus
    stage: str


class ProjectState(BaseModel):
    name: str = "AutoEdit Project"
    duration: float = 0
    segments: list[HighlightSegment] = Field(default_factory=list)
    captions: list[CaptionSegment] = Field(default_factory=list)
    waveform: list[float] = Field(default_factory=list)


class ProjectResponse(ProjectState):
    job_id: str
    original_filename: str | None = None
