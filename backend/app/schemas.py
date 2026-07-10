from enum import StrEnum
from typing import Any

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

TIMELINE_FRAME_RATE = 30.0
TIMELINE_TIMECODE_MODE = "non_drop"


def _snap_seconds_to_30p(value: Any) -> float:
    try:
        seconds = float(value)
    except (TypeError, ValueError):
        seconds = 0.0
    if seconds <= 0:
        return 0.0
    return round(round(seconds * TIMELINE_FRAME_RATE) / TIMELINE_FRAME_RATE, 6)


def _snap_optional_seconds_to_30p(value: Any) -> float | None:
    if value is None:
        return None
    return _snap_seconds_to_30p(value)


class JobStatus(StrEnum):
    queued = "queued"
    processing = "processing"
    completed = "completed"
    rendering = "rendering"
    rendered = "rendered"
    cancelled = "cancelled"
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

    @field_validator("start", "end", mode="before")
    @classmethod
    def timeline_seconds_are_30p(cls, value: Any) -> float:
        return _snap_seconds_to_30p(value)


class TranscriptSegment(BaseModel):
    start: float
    end: float
    text: str
    words: list[TranscriptWord] = Field(default_factory=list)

    @field_validator("start", "end", mode="before")
    @classmethod
    def timeline_seconds_are_30p(cls, value: Any) -> float:
        return _snap_seconds_to_30p(value)


class CaptionSegment(BaseModel):
    order: int = 0
    start: float
    end: float
    text: str
    enabled: bool = True

    @field_validator("start", "end", mode="before")
    @classmethod
    def timeline_seconds_are_30p(cls, value: Any) -> float:
        return _snap_seconds_to_30p(value)

    @field_validator("end")
    @classmethod
    def end_must_be_after_start(cls, value: float, info: Any) -> float:
        start = info.data.get("start")
        if start is not None and value <= start:
            raise ValueError("end must be greater than start")
        return value


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
    focus_x: float = 0.5
    focus_y: float = 0.42
    focus_confidence: float = 0.0
    focus_keyframes: list[dict[str, float]] = Field(default_factory=list)
    topic_id: int = 0
    audio_start: float | None = None
    audio_end: float | None = None
    audio_muted: bool = False
    audio_volume: float = 1.0
    audio_pan: float = 0.0
    audio_normalize: bool = False
    audio_loudness_target: float = -14.0
    audio_linked: bool = True
    audio_channel_1_enabled: bool = True
    audio_channel_2_enabled: bool = True
    audio_source_channel_left: int = 1
    audio_source_channel_right: int = 2
    playback_speed: float = 1.0
    transition_type: str = "cut"
    transition_duration: float = 0.0
    audio_fade_in: float = 0.0
    audio_fade_out: float = 0.0
    score: float = 0.0
    tags: list[str] = Field(default_factory=list)

    @field_validator("start", "end", "audio_start", "audio_end", mode="before")
    @classmethod
    def timeline_seconds_are_30p(cls, value: Any) -> float | None:
        return _snap_optional_seconds_to_30p(value)

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

    @field_validator("audio_loudness_target")
    @classmethod
    def audio_loudness_target_must_be_safe(cls, value: float) -> float:
        return max(-24.0, min(float(value), -12.0))

    @field_validator("audio_source_channel_left", "audio_source_channel_right")
    @classmethod
    def audio_source_channel_must_be_safe(cls, value: int) -> int:
        return max(1, min(int(value), 64))

    @field_validator("playback_speed")
    @classmethod
    def playback_speed_must_be_safe(cls, value: float) -> float:
        return max(0.25, min(float(value), 4.0))

    @field_validator("transition_type", mode="before")
    @classmethod
    def transition_type_must_be_supported(cls, value: Any) -> str:
        normalized = str(value or "cut").strip().lower()
        return normalized if normalized in {"cut", "cross_dissolve", "dip_black"} else "cut"

    @field_validator("transition_duration")
    @classmethod
    def transition_duration_must_be_safe(cls, value: float) -> float:
        return max(0.0, min(_snap_seconds_to_30p(value), 3.0))

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

    @field_validator("focus_x", "focus_y", "focus_confidence")
    @classmethod
    def focus_value_must_be_safe(cls, value: float) -> float:
        return max(0.0, min(float(value), 1.0))

    @field_validator("focus_keyframes", mode="before")
    @classmethod
    def focus_keyframes_must_be_safe(cls, value: Any) -> list[dict[str, float]]:
        if not isinstance(value, list):
            return []
        output: list[dict[str, float]] = []
        for item in value:
            if not isinstance(item, dict):
                continue
            try:
                output.append(
                    {
                        "time": max(0.0, float(item.get("time", 0.0))),
                        "x": max(0.0, min(float(item.get("x", 0.5)), 1.0)),
                        "y": max(0.0, min(float(item.get("y", 0.42)), 1.0)),
                    }
                )
            except (TypeError, ValueError):
                continue
        return output[:48]

    @field_validator("topic_id")
    @classmethod
    def topic_id_must_be_safe(cls, value: int) -> int:
        return max(0, int(value))

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


class LocalPreviewRequest(BaseModel):
    path: str
    start_seconds: float = 0.0
    duration_seconds: float | None = None


class LocalPreviewResponse(BaseModel):
    preview_url: str
    preview_path: str = ""
    cached: bool = False
    source_start: float = 0.0
    duration: float = 0.0


class LocalThumbnailRequest(BaseModel):
    path: str
    time_seconds: float = Field(default=0.0, ge=0.0)
    width: int = Field(default=320, ge=160, le=640)


class LocalThumbnailResponse(BaseModel):
    thumbnail_url: str
    thumbnail_path: str = ""
    cached: bool = False
    source_time: float = 0.0
    width: int = 320


class StorageCategoryUsage(BaseModel):
    key: str
    label: str
    bytes: int = 0
    files: int = 0
    reclaimable_bytes: int = 0
    protected: bool = False


class StorageUsageResponse(BaseModel):
    data_dir: str
    total_bytes: int = 0
    reclaimable_bytes: int = 0
    retention_hours: int = 24
    categories: list[StorageCategoryUsage] = Field(default_factory=list)
    protected_items: list[str] = Field(default_factory=list)


class StorageCleanupRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    active_job_id: str | None = Field(default=None, max_length=64)
    retention_hours: int = Field(default=24, ge=1, le=720)


class StorageCleanupResponse(BaseModel):
    freed_bytes: int = 0
    deleted_files: int = 0
    skipped_files: int = 0
    before: StorageUsageResponse
    after: StorageUsageResponse


class MediaProbeResponse(BaseModel):
    path: str
    filename: str
    container: str = ""
    format_long_name: str = ""
    duration: float = 0.0
    bit_rate: int = 0
    video_codec: str = ""
    video_codec_long_name: str = ""
    pixel_format: str = ""
    width: int = 0
    height: int = 0
    frame_rate: float = 0.0
    source_frame_rate: float = 0.0
    source_timecode: str | None = None
    source_drop_frame: bool = False
    timeline_frame_rate: float = TIMELINE_FRAME_RATE
    timeline_timecode_mode: str = TIMELINE_TIMECODE_MODE
    timeline_timebase: str = "30p NDF"
    timecode: str | None = None
    audio_stream_count: int = 0
    audio_channel_count: int = 0
    audio_summary: str = ""
    is_mxf: bool = False
    mxf_operational_pattern: str = ""
    can_analyze: bool = False
    warnings: list[str] = Field(default_factory=list)

    @field_validator("timeline_frame_rate", mode="before")
    @classmethod
    def timeline_frame_rate_is_30p(cls, value: Any) -> float:
        return TIMELINE_FRAME_RATE

    @field_validator("timeline_timecode_mode", mode="before")
    @classmethod
    def timeline_timecode_mode_is_non_drop(cls, value: Any) -> str:
        return TIMELINE_TIMECODE_MODE


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


class TimelineResponse(BaseModel):
    job_id: str
    duration: float
    segments: list[HighlightSegment]
    transcript: list[TranscriptSegment] = Field(default_factory=list)
    captions: list[CaptionSegment] = Field(default_factory=list)
    waveform: list[float] = Field(default_factory=list)


class TimelineMarker(BaseModel):
    id: int = 0
    seconds: float
    label: str = "Marker"
    color: str = "amber"
    note: str = ""
    enabled: bool = True

    @field_validator("seconds", mode="before")
    @classmethod
    def seconds_must_be_non_negative(cls, value: float) -> float:
        return _snap_seconds_to_30p(value)


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
    aspect_ratio: str | None = None


class BatchRenderItemResult(BaseModel):
    label: str = "Shorts"
    path: str | None = None
    url: str = ""
    output_name: str = ""
    kind: str = "video"
    aspect_ratio: str = ""
    duration_seconds: float = 0.0
    size_bytes: int = 0
    warnings: list[str] = Field(default_factory=list)
    segments: list[HighlightSegment] = Field(default_factory=list)


class JobStatusResponse(BaseModel):
    job_id: str
    status: JobStatus
    stage: str
    progress: int
    message: str = ""
    duration: float | None = None
    original_filename: str | None = None
    segments: list[HighlightSegment] = Field(default_factory=list)
    render_path: str | None = None
    render_url: str | None = None
    render_duration_seconds: float | None = None
    render_size_bytes: int | None = None
    render_warnings: list[str] = Field(default_factory=list)
    batch_render_items: list[BatchRenderItemResult] = Field(default_factory=list)
    render_manifest_items: list[BatchRenderItemResult] = Field(default_factory=list)
    error: str | None = None
    style_profile: StyleProfile | None = None
    analysis_warnings: list[str] = Field(default_factory=list)


class JobSummaryResponse(BaseModel):
    job_id: str
    status: JobStatus
    stage: str
    progress: int = 0
    message: str = ""
    project_name: str = ""
    original_filename: str = ""
    video_path: str = ""
    duration: float = 0.0
    import_mode: str = ""
    source_exists: bool = False
    has_timeline: bool = False
    segment_count: int = 0
    render_exists: bool = False
    render_path: str | None = None
    render_url: str | None = None
    can_resume: bool = False
    created_at: str | None = None
    updated_at: str | None = None


class BatchRenderRequest(BaseModel):
    items: list[BatchRenderItem]
    captions: list[CaptionSegment] = Field(default_factory=list)
    caption_style: CaptionStyle = Field(default_factory=CaptionStyle)
    aspect_ratio: str = "9:16"
    include_captions: bool = True


def _normalize_shorts_candidate_payloads(value: Any) -> list[dict[str, Any]]:
    if not isinstance(value, list):
        return []
    normalized: list[dict[str, Any]] = []
    for item in value:
        if not isinstance(item, dict):
            continue
        candidate = dict(item)
        raw_segments = candidate.get("segments")
        if isinstance(raw_segments, list):
            candidate["segments"] = [
                _normalize_shorts_candidate_segment(segment)
                for segment in raw_segments
            ]
        normalized.append(candidate)
    return normalized


def _normalize_shorts_candidate_segment(value: Any) -> Any:
    if not isinstance(value, dict):
        return value
    try:
        return HighlightSegment(**value).model_dump()
    except Exception:
        return value


class RenderResponse(BaseModel):
    job_id: str
    render_task_id: str
    status: JobStatus
    stage: str


class ProjectState(BaseModel):
    name: str = "AutoEdit Project"
    original_path: str | None = None
    duration: float = 0
    timeline_frame_rate: float = TIMELINE_FRAME_RATE
    timeline_timecode_mode: str = TIMELINE_TIMECODE_MODE
    segments: list[HighlightSegment] = Field(default_factory=list)
    transcript: list[TranscriptSegment] = Field(default_factory=list)
    captions: list[CaptionSegment] = Field(default_factory=list)
    waveform: list[float] = Field(default_factory=list)
    timeline_markers: list[TimelineMarker] = Field(default_factory=list)
    shorts_candidates: list[dict[str, Any]] = Field(default_factory=list)
    selected_shorts_id: int | None = None
    include_captions: bool = True
    caption_style_preset: str = "news"
    export_aspect_ratio: str = "16:9"
    selected_export_profiles: list[str] = Field(default_factory=list)
    mark_in: float | None = None
    mark_out: float | None = None

    @field_validator("timeline_frame_rate", mode="before")
    @classmethod
    def timeline_frame_rate_is_30p(cls, value: Any) -> float:
        return TIMELINE_FRAME_RATE

    @field_validator("timeline_timecode_mode", mode="before")
    @classmethod
    def timeline_timecode_mode_is_non_drop(cls, value: Any) -> str:
        return TIMELINE_TIMECODE_MODE

    @field_validator("mark_in", "mark_out", mode="before")
    @classmethod
    def marks_are_30p(cls, value: Any) -> float | None:
        return _snap_optional_seconds_to_30p(value)

    @field_validator("shorts_candidates", mode="before")
    @classmethod
    def shorts_candidates_are_30p(cls, value: Any) -> list[dict[str, Any]]:
        return _normalize_shorts_candidate_payloads(value)

    @model_validator(mode="after")
    def export_profiles_are_supported(self) -> "ProjectState":
        supported = ("16:9", "9:16", "1:1")
        requested = self.selected_export_profiles
        normalized = [profile for profile in supported if profile in requested]
        fallback = (
            self.export_aspect_ratio
            if self.export_aspect_ratio in supported
            else "16:9"
        )
        self.selected_export_profiles = normalized or [fallback]
        return self


class ProjectResponse(ProjectState):
    job_id: str
    original_filename: str | None = None
