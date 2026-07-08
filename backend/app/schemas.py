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


class StyleStatus(StrEnum):
    queued = "queued"
    processing = "processing"
    ready = "ready"
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


class CaptionStyle(BaseModel):
    preset: str = "news"
    font_name: str = "Arial"
    font_size: int = 24
    primary_color: str = "&H00FFFFFF"
    outline_color: str = "&H90000000"
    outline: int = 2
    shadow: int = 0
    alignment: int = 2
    margin_v: int = 72

    @field_validator("font_size")
    @classmethod
    def font_size_must_be_safe(cls, value: int) -> int:
        return max(14, min(int(value), 72))

    @field_validator("outline")
    @classmethod
    def outline_must_be_safe(cls, value: int) -> int:
        return max(0, min(int(value), 8))

    @field_validator("shadow")
    @classmethod
    def shadow_must_be_safe(cls, value: int) -> int:
        return max(0, min(int(value), 8))

    @field_validator("alignment")
    @classmethod
    def alignment_must_be_safe(cls, value: int) -> int:
        return max(1, min(int(value), 9))

    @field_validator("margin_v")
    @classmethod
    def margin_v_must_be_safe(cls, value: int) -> int:
        return max(0, min(int(value), 360))


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


class LocalImportRequest(BaseModel):
    path: str
    display_name: str | None = None
    style_id: str | None = None


class MediaProbeRequest(BaseModel):
    path: str


class MediaProbeResponse(BaseModel):
    path: str
    filename: str
    container: str = ""
    format_long_name: str = ""
    duration: float = 0.0
    bit_rate: int = 0
    video_codec: str = ""
    video_codec_long_name: str = ""
    width: int = 0
    height: int = 0
    frame_rate: float = 0.0
    timecode: str | None = None
    audio_stream_count: int = 0
    audio_summary: str = ""
    is_mxf: bool = False
    mxf_operational_pattern: str = ""
    can_analyze: bool = False
    warnings: list[str] = Field(default_factory=list)


class LocalStyleTrainingRequest(BaseModel):
    name: str = "Company Reference Style"
    file_paths: list[str] = Field(default_factory=list)
    urls: list[str] = Field(default_factory=list)


class StyleReferenceSource(BaseModel):
    label: str
    kind: str = "file"
    path: str | None = None
    url: str | None = None
    duration: float = 0.0
    scene_count: int = 0
    scene_rate_per_minute: float = 0.0
    average_cut_seconds: float = 0.0
    silence_ratio: float = 0.0
    speech_ratio: float = 0.0
    error: str | None = None


class StyleProfile(BaseModel):
    style_id: str
    name: str = "Reference Style"
    status: StyleStatus = StyleStatus.queued
    message: str = ""
    progress: int = 0
    source_count: int = 0
    ready_source_count: int = 0
    pace: str = "balanced"
    average_cut_seconds: float = 6.0
    median_cut_seconds: float = 6.0
    hook_window_seconds: float = 15.0
    silence_aggressiveness: float = 0.6
    visual_change_sensitivity: float = 0.5
    target_segment_seconds_min: float = 18.0
    target_segment_seconds_ideal: float = 36.0
    target_segment_seconds_max: float = 52.0
    prefer_news_structure: bool = True
    prefer_shorts_structure: bool = False
    caption_density: str = "medium"
    transition_style: str = "hard_cut"
    scoring_weights: dict[str, float] = Field(default_factory=dict)
    sources: list[StyleReferenceSource] = Field(default_factory=list)
    error: str | None = None
    created_at: str | None = None
    updated_at: str | None = None


class StyleTrainingResponse(BaseModel):
    style_id: str
    status: StyleStatus
    progress: int
    message: str = ""
    profile: StyleProfile | None = None


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
    style_profile: StyleProfile | None = None


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
    caption_style: CaptionStyle = Field(default_factory=CaptionStyle)
    aspect_ratio: str = "16:9"
    include_captions: bool = False
    output_name: str = "youtube_highlights.mp4"


class BatchRenderItem(BaseModel):
    label: str = "shorts"
    segments: list[HighlightSegment]
    output_name: str = "shorts.mp4"


class BatchRenderRequest(BaseModel):
    items: list[BatchRenderItem]
    captions: list[CaptionSegment] = Field(default_factory=list)
    caption_style: CaptionStyle = Field(default_factory=CaptionStyle)
    aspect_ratio: str = "9:16"
    include_captions: bool = True


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
