import json
import re
from typing import Any

from app.config import get_settings
from app.services.editing_skills import (
    enrich_highlights_with_skill_scores,
    select_highlights_with_skills,
)


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
You are a senior video editor for YouTube long-form and newsroom-style reports.

Analyze the timestamped transcript and select only the most interesting,
important, or curiosity-driving moments. The final combined duration must be
between {target_min_seconds} and {target_max_seconds} seconds when possible.

Return ONLY a strict JSON array. Do not wrap it in markdown. Do not add prose.
Each item must follow this exact schema:
[
  {{
    "start": 124.5,
    "end": 155.2,
    "reason": "핵심 주제 결론 및 강조 부분",
    "score": 8.5,
    "tags": ["핵심", "문제해결"]
  }}
]

Rules:
- start/end are seconds as numbers, not strings.
- Keep chronological order.
- Avoid tiny fragments under 8 seconds unless context requires them.
- Include a Korean reason explaining why viewers would care.
- Add score from 0 to 10 and 1-4 Korean tags explaining the editing value.
- Prefer segments with a clear hook, concrete information, conflict/problem,
  solution, emotion, question, or strong conclusion.
- Avoid filler-heavy chatter, subscribe/like calls, repeated greetings, and
  setup that does not help the selected clip make sense.
- Preserve enough context so each clip still makes sense when watched alone.
- Select enough segments to make a 3-4 minute edit when the source duration allows it.

News/editorial rules:
- If this is news, politics, finance, public safety, legal, medical, or public
  interest content, prioritize editorial clarity over entertainment.
- Build a balanced sequence: lead/event, verified facts or data, impact on
  people, official response or opposing view, and consequence/next step.
- Prefer attributed claims: "according to", "said", "announced", "reported",
  "에 따르면", "밝혔습니다", "말했습니다".
- Avoid unverified rumors, speculation, sensational wording, or claims without
  context. Do not make a clip imply certainty when the transcript does not.
- Use Korean tags such as "뉴스핵심", "근거", "영향", "대응", "출처확인", "시간축".

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
    return enrich_highlights_with_skill_scores(_parse_json_array(content), transcript)


def fallback_highlights(
    transcript: list[dict[str, Any]],
    duration: float,
) -> list[dict[str, Any]]:
    settings = get_settings()
    return select_highlights_with_skills(
        transcript,
        duration,
        settings.target_highlight_seconds_min,
        settings.target_highlight_seconds_max,
    )


def analyze_highlights(
    transcript: list[dict[str, Any]],
    duration: float,
) -> list[dict[str, Any]]:
    settings = get_settings()
    if settings.use_openai_llm and settings.openai_api_key:
        try:
            return analyze_with_openai(transcript)
        except Exception:
            return fallback_highlights(transcript, duration)
    return fallback_highlights(transcript, duration)
