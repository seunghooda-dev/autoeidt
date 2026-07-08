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
    local_whisper_model: str = "tiny"
    local_whisper_device: str = "cpu"
    local_whisper_compute_type: str = "int8"

    target_highlight_seconds_min: int = 180
    target_highlight_seconds_max: int = 240
    silence_noise_db: str = "-35dB"
    silence_min_duration: float = 0.8
    visual_motion_threshold: float = 1.7
    scene_change_threshold: float = 0.35
    prefer_gpu_encoding: bool = True

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
