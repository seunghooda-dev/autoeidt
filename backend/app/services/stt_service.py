from pathlib import Path
from typing import Any

from app.config import get_settings


def _plain_model(value: Any) -> dict[str, Any]:
    if hasattr(value, "model_dump"):
        return value.model_dump()
    if isinstance(value, dict):
        return value
    return dict(value)


def _normalize_transcript(payload: dict[str, Any]) -> list[dict[str, Any]]:
    raw_segments = payload.get("segments") or []
    raw_words = payload.get("words") or []
    normalized: list[dict[str, Any]] = []

    for segment in raw_segments:
        start = float(segment.get("start", 0))
        end = float(segment.get("end", start))
        words = [
            {
                "start": float(word.get("start", start)),
                "end": float(word.get("end", end)),
                "word": str(word.get("word", "")).strip(),
            }
            for word in raw_words
            if start <= float(word.get("start", -1)) <= end
        ]
        normalized.append(
            {
                "start": start,
                "end": end,
                "text": str(segment.get("text", "")).strip(),
                "words": words,
            }
        )

    if normalized:
        return normalized

    text = str(payload.get("text", "")).strip()
    return [{"start": 0.0, "end": 0.0, "text": text, "words": []}] if text else []


def transcribe_with_openai(audio_path: Path) -> list[dict[str, Any]]:
    settings = get_settings()
    if not settings.openai_api_key:
        raise RuntimeError("OPENAI_API_KEY is not configured")

    from openai import OpenAI

    client = OpenAI(api_key=settings.openai_api_key)
    with audio_path.open("rb") as audio_file:
        transcription = client.audio.transcriptions.create(
            model=settings.openai_transcription_model,
            file=audio_file,
            response_format="verbose_json",
            timestamp_granularities=["segment", "word"],
        )
    return _normalize_transcript(_plain_model(transcription))


def fallback_transcript(duration: float) -> list[dict[str, Any]]:
    if duration <= 0:
        duration = 60.0
    chunk = 30.0
    transcript: list[dict[str, Any]] = []
    cursor = 0.0
    index = 1
    while cursor < duration:
        end = min(duration, cursor + chunk)
        transcript.append(
            {
                "start": round(cursor, 1),
                "end": round(end, 1),
                "text": (
                    f"개발용 자동 스크립트 {index}. 실제 OPENAI_API_KEY를 설정하면 "
                    "Whisper 타임스탬프 기반 문장 데이터로 대체됩니다."
                ),
                "words": [],
            }
        )
        cursor = end
        index += 1
    return transcript


def transcribe_audio(audio_path: Path, duration: float) -> list[dict[str, Any]]:
    settings = get_settings()
    if settings.use_openai_whisper and settings.openai_api_key:
        return transcribe_with_openai(audio_path)
    return fallback_transcript(duration)
