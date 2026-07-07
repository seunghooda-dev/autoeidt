import json
import re
from typing import Any

from app.config import get_settings


KEYWORD_WEIGHTS = {
    "중요": 3,
    "핵심": 3,
    "결론": 3,
    "문제": 2,
    "해결": 2,
    "비밀": 2,
    "실수": 2,
    "방법": 2,
    "이유": 2,
    "important": 3,
    "key": 3,
    "secret": 2,
    "mistake": 2,
    "why": 2,
    "how": 2,
}


def build_highlight_prompt(
    transcript: list[dict[str, Any]],
    target_min_seconds: int,
    target_max_seconds: int,
) -> str:
    compact_transcript = [
        {
            "start": round(float(item["start"]), 1),
            "end": round(float(item["end"]), 1),
            "text": item.get("text", ""),
        }
        for item in transcript
    ]
    return f"""
You are a senior video editor for YouTube long-form highlight videos.

Analyze the timestamped transcript and select only the most interesting,
important, or curiosity-driving moments. The final combined duration must be
between {target_min_seconds} and {target_max_seconds} seconds when possible.

Return ONLY a strict JSON array. Do not wrap it in markdown. Do not add prose.
Each item must follow this exact schema:
[
  {{"start": 124.5, "end": 155.2, "reason": "핵심 주제 결론 및 강조 부분"}}
]

Rules:
- start/end are seconds as numbers, not strings.
- Keep chronological order.
- Avoid tiny fragments under 8 seconds unless context requires them.
- Include a Korean reason explaining why viewers would care.
- Select enough segments to make a 3-4 minute edit when the source duration allows it.

Transcript JSON:
{json.dumps(compact_transcript, ensure_ascii=False)}
""".strip()


def _parse_json_array(text: str) -> list[dict[str, Any]]:
    stripped = text.strip()
    if stripped.startswith("```"):
        stripped = re.sub(r"^```(?:json)?", "", stripped).strip()
        stripped = re.sub(r"```$", "", stripped).strip()

    try:
        parsed = json.loads(stripped)
    except json.JSONDecodeError:
        match = re.search(r"\[[\s\S]*\]", stripped)
        if not match:
            raise
        parsed = json.loads(match.group(0))

    if not isinstance(parsed, list):
        raise ValueError("LLM response must be a JSON array")
    return parsed


def analyze_with_openai(transcript: list[dict[str, Any]]) -> list[dict[str, Any]]:
    settings = get_settings()
    if not settings.openai_api_key:
        raise RuntimeError("OPENAI_API_KEY is not configured")

    from openai import OpenAI

    client = OpenAI(api_key=settings.openai_api_key)
    response = client.chat.completions.create(
        model=settings.openai_llm_model,
        temperature=0.2,
        messages=[
            {
                "role": "system",
                "content": "Return only valid JSON. Never include markdown fences.",
            },
            {
                "role": "user",
                "content": build_highlight_prompt(
                    transcript,
                    settings.target_highlight_seconds_min,
                    settings.target_highlight_seconds_max,
                ),
            },
        ],
    )
    content = response.choices[0].message.content or "[]"
    return _parse_json_array(content)


def _score_window(items: list[dict[str, Any]]) -> float:
    text = " ".join(str(item.get("text", "")) for item in items)
    score = min(len(text) / 80.0, 4.0)
    lowered = text.lower()
    for keyword, weight in KEYWORD_WEIGHTS.items():
        if keyword in lowered:
            score += weight
    return score


def fallback_highlights(
    transcript: list[dict[str, Any]],
    duration: float,
) -> list[dict[str, Any]]:
    settings = get_settings()
    if not transcript:
        end = min(duration or 60.0, 45.0)
        return [{"start": 0.0, "end": end, "reason": "개발용 기본 하이라이트 구간"}]

    windows: list[dict[str, Any]] = []
    current: list[dict[str, Any]] = []
    current_start = float(transcript[0]["start"])

    for item in transcript:
        current.append(item)
        span = float(item["end"]) - current_start
        if span >= 40.0:
            windows.append(
                {
                    "start": current_start,
                    "end": float(item["end"]),
                    "items": current,
                    "score": _score_window(current),
                }
            )
            current = []
            current_start = float(item["end"])

    if current:
        windows.append(
            {
                "start": current_start,
                "end": float(current[-1]["end"]),
                "items": current,
                "score": _score_window(current),
            }
        )

    selected: list[dict[str, Any]] = []
    total = 0.0
    for window in sorted(windows, key=lambda item: item["score"], reverse=True):
        length = float(window["end"]) - float(window["start"])
        if total >= settings.target_highlight_seconds_min:
            break
        if total + length > settings.target_highlight_seconds_max and total > 0:
            continue
        selected.append(window)
        total += length

    if not selected:
        selected = windows[:1]

    selected.sort(key=lambda item: float(item["start"]))
    return [
        {
            "start": round(float(item["start"]), 1),
            "end": round(float(item["end"]), 1),
            "reason": "개발용 휴리스틱으로 선택한 정보 밀도 높은 구간",
        }
        for item in selected
    ]


def analyze_highlights(
    transcript: list[dict[str, Any]],
    duration: float,
) -> list[dict[str, Any]]:
    settings = get_settings()
    if settings.use_openai_llm and settings.openai_api_key:
        return analyze_with_openai(transcript)
    return fallback_highlights(transcript, duration)
