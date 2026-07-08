from functools import lru_cache
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


@lru_cache(maxsize=2)
def _local_whisper_model(
    model_name: str,
    device: str,
    compute_type: str,
) -> Any:
    from faster_whisper import WhisperModel

    return WhisperModel(
        model_name,
        device=device,
        compute_type=compute_type,
    )


def transcribe_with_local_whisper(audio_path: Path) -> list[dict[str, Any]]:
    settings = get_settings()
    model = _local_whisper_model(
        settings.local_whisper_model,
        settings.local_whisper_device,
        settings.local_whisper_compute_type,
    )
    segments, _info = model.transcribe(
        str(audio_path),
        beam_size=5,
        vad_filter=True,
        word_timestamps=True,
    )
    transcript: list[dict[str, Any]] = []
    for segment in segments:
        words = [
            {
                "start": float(word.start or segment.start),
                "end": float(word.end or segment.end),
                "word": str(word.word or "").strip(),
            }
            for word in (segment.words or [])
            if str(word.word or "").strip()
        ]
        text = str(segment.text or "").strip()
        if not text:
            continue
        transcript.append(
            {
                "start": float(segment.start),
                "end": float(segment.end),
                "text": text,
                "source": "local_whisper",
                "words": words,
            }
        )
    return transcript


def fallback_transcript(
    duration: float,
    reason: str = "stt_not_available",
) -> list[dict[str, Any]]:
    if duration <= 0:
        duration = 60.0
    chunk = 30.0
    transcript: list[dict[str, Any]] = []
    cursor = 0.0
    while cursor < duration:
        end = min(duration, cursor + chunk)
        transcript.append(
            {
                "start": round(cursor, 1),
                "end": round(end, 1),
                "text": (
                    "음성 인식이 설정되지 않아 실제 대화 내용은 분석되지 않았습니다."
                ),
                "source": "fallback_stt",
                "fallback_reason": reason,
                "words": [],
            }
        )
        cursor = end
    return transcript


def transcribe_audio(audio_path: Path, duration: float) -> list[dict[str, Any]]:
    settings = get_settings()
    if settings.use_openai_whisper and settings.openai_api_key:
        return transcribe_with_openai(audio_path)
    if settings.use_local_whisper:
        try:
            transcript = transcribe_with_local_whisper(audio_path)
            if transcript:
                return transcript
            return fallback_transcript(duration, "local_whisper_empty_transcript")
        except Exception as exc:
            return fallback_transcript(duration, f"local_whisper_failed: {exc}")
    return fallback_transcript(duration, "openai_key_missing_and_local_whisper_disabled")
