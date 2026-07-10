from functools import lru_cache
from pathlib import Path

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "AI Highlight Editor"
    api_prefix: str = "/api"
    cors_origins: list[str] = Field(default_factory=lambda: ["*"])

    data_dir: Path = Path(__file__).resolve().parents[1] / "data"
    redis_url: str = "redis://localhost:6379/0"
    task_runner: str = "celery"

    openai_api_key: str | None = None
    openai_transcription_model: str = "whisper-1"
    openai_llm_model: str = "gpt-4.1-mini"
    use_openai_whisper: bool = True
    use_openai_llm: bool = True
    use_local_whisper: bool = True
    local_whisper_model: str = "auto"
    local_whisper_device: str = "auto"
    local_whisper_compute_type: str = "auto"
    local_whisper_language: str | None = "ko"
    local_whisper_initial_prompt: str = (
        "한국어 방송 원고입니다. 인명, 지명, 기관명, 숫자, 단위를 정확히 "
        "표기하고 문장부호를 자연스럽게 사용하세요."
    )
    local_whisper_hotwords: str = (
        "정부 국회 법원 검찰 경찰 소방 당국 위원회 공식 발표 보고서 "
        "인터뷰 현장 취재 기자 앵커 피해 대응 조사"
    )
    local_whisper_beam_size: int = 3

    target_highlight_seconds_min: int = 180
    target_highlight_seconds_max: int = 240
    silence_noise_db: str = "-35dB"
    silence_min_duration: float = 0.8
    visual_motion_threshold: float = 1.7
    scene_change_threshold: float = 0.35
    prefer_gpu_encoding: bool = True
    preview_proxy_seconds: int = 12

    upload_max_mb: int = 4096

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )


@lru_cache
def get_settings() -> Settings:
    settings = Settings()
    settings.data_dir.mkdir(parents=True, exist_ok=True)
    return settings
