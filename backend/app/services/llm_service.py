import json
import re
from typing import Any

from app.config import get_settings
from app.services.editing_skills import (
    enrich_highlights_with_skill_scores,
    select_highlights_with_skills,
)


def _overlap_seconds(
    a_start: float,
    a_end: float,
    b_start: float,
    b_end: float,
) -> float:
    return max(0.0, min(a_end, b_end) - max(a_start, b_start))


def _silence_seconds(item: Any, key: str) -> float:
    if isinstance(item, dict):
        value = item.get(key, 0.0)
    else:
        value = getattr(item, key, 0.0)
    try:
        return float(value)
    except (TypeError, ValueError):
        return 0.0


def _coerce_silence_ranges(
    silence_ranges: list[Any] | None,
    duration: float,
) -> list[tuple[float, float]]:
    ranges: list[tuple[float, float]] = []
    for item in silence_ranges or []:
        start = max(0.0, min(_silence_seconds(item, "start"), duration))
        end = max(0.0, min(_silence_seconds(item, "end"), duration))
        if end > start:
            ranges.append((start, end))
    ranges.sort()

    merged: list[tuple[float, float]] = []
    for start, end in ranges:
        if not merged or start > merged[-1][1]:
            merged.append((start, end))
        else:
            merged[-1] = (merged[-1][0], max(merged[-1][1], end))
    return merged


def _speech_ranges_from_silence(
    duration: float,
    silence_ranges: list[Any] | None,
    min_speech_seconds: float = 2.0,
) -> list[tuple[float, float]]:
    silences = _coerce_silence_ranges(silence_ranges, duration)
    if not silences:
        return []

    speech: list[tuple[float, float]] = []
    cursor = 0.0
    for start, end in silences:
        if start - cursor >= min_speech_seconds:
            speech.append((cursor, start))
        cursor = max(cursor, end)
    if duration - cursor >= min_speech_seconds:
        speech.append((cursor, duration))
    return speech


def _fallback_target_total(
    duration: float,
    target_min_seconds: float,
    target_max_seconds: float,
) -> float:
    return min(
        float(target_max_seconds),
        max(45.0, min(float(target_min_seconds), duration * 0.35)),
    )


def _fallback_clip_shape(
    duration: float,
    target_total: float,
) -> tuple[int, float]:
    clip_count = max(1, min(6, round(target_total / 45.0)))
    clip_length = min(
        60.0,
        max(20.0, target_total / clip_count, duration / (clip_count * 3)),
    )
    return clip_count, min(clip_length, duration)


def _audio_activity_review_highlights(
    duration: float,
    target_total: float,
    clip_count: int,
    clip_length: float,
    speech_ranges: list[tuple[float, float]],
) -> list[dict[str, Any]]:
    if not speech_ranges:
        return []

    windows: list[dict[str, Any]] = []
    seen: set[tuple[int, int]] = set()
    for index, (speech_start, speech_end) in enumerate(speech_ranges):
        cluster_start = speech_start
        cluster_end = speech_end
        speech_seconds = speech_end - speech_start
        cursor = index + 1
        while cursor < len(speech_ranges):
            next_start, next_end = speech_ranges[cursor]
            gap = next_start - cluster_end
            if gap > 12.0 and cluster_end - cluster_start >= clip_length * 0.55:
                break
            if next_end - cluster_start > clip_length * 1.25:
                break
            cluster_end = next_end
            speech_seconds += next_end - next_start
            cursor += 1

        cluster_duration = cluster_end - cluster_start
        window_length = min(
            duration,
            max(
                min(clip_length, duration),
                min(clip_length * 0.75, cluster_duration + 2.0),
            ),
        )
        window_length = max(2.0, min(window_length, duration))
        center = (cluster_start + cluster_end) / 2
        start = max(
            0.0,
            min(center - window_length / 2, duration - window_length),
        )
        end = min(duration, start + window_length)
        speech_overlap = sum(
            _overlap_seconds(start, end, item_start, item_end)
            for item_start, item_end in speech_ranges
        )
        density = speech_overlap / max(end - start, 0.001)
        center_bias = 1.0 - min(
            abs((center / max(duration, 0.001)) - 0.45),
            0.45,
        )
        score = density * 0.78 + center_bias * 0.22
        key = (round(start), round(end))
        if key in seen:
            continue
        seen.add(key)
        windows.append(
            {
                "start": start,
                "end": end,
                "density": density,
                "score": score,
                "speech_seconds": speech_overlap,
            }
        )

    windows.sort(
        key=lambda item: (item["score"], item["speech_seconds"]),
        reverse=True,
    )
    selected: list[dict[str, Any]] = []
    selected_total = 0.0
    for window in windows:
        start = float(window["start"])
        end = float(window["end"])
        duration_seconds = end - start
        if any(
            _overlap_seconds(start, end, float(item["start"]), float(item["end"]))
            / max(
                min(duration_seconds, float(item["end"]) - float(item["start"])),
                0.001,
            )
            > 0.45
            for item in selected
        ):
            continue
        density = float(window["density"])
        selected.append(
            {
                "start": round(start, 3),
                "end": round(end, 3),
                "reason": "STT 없이 오디오 활동과 무음 탐지를 기준으로 잡은 검토용 후보 구간입니다.",
                "script": "",
                "source": "fallback-audio-review",
                "score": round(3.0 + density * 4.0, 2),
                "tags": ["검토필요", "오디오활성", "STT미설정"],
            }
        )
        selected_total += duration_seconds
        if len(selected) >= clip_count and selected_total >= target_total * 0.85:
            break

    selected.sort(key=lambda item: float(item["start"]))
    return selected


def build_highlight_prompt(
    transcript: list[dict[str, Any]],
    target_min_seconds: int,
    target_max_seconds: int,
    style_profile: dict[str, Any] | None = None,
) -> str:
    compact_transcript = [
        {
            "start": round(float(item["start"]), 1),
            "end": round(float(item["end"]), 1),
            "text": item.get("text", ""),
        }
        for item in transcript
    ]
    style_block = ""
    if style_profile:
        style_block = f"""

Reference editing style profile:
{json.dumps({
    "pace": style_profile.get("pace"),
    "average_cut_seconds": style_profile.get("average_cut_seconds"),
    "hook_window_seconds": style_profile.get("hook_window_seconds"),
    "silence_aggressiveness": style_profile.get("silence_aggressiveness"),
    "target_segment_seconds_min": style_profile.get("target_segment_seconds_min"),
    "target_segment_seconds_ideal": style_profile.get("target_segment_seconds_ideal"),
    "target_segment_seconds_max": style_profile.get("target_segment_seconds_max"),
    "prefer_news_structure": style_profile.get("prefer_news_structure"),
    "prefer_shorts_structure": style_profile.get("prefer_shorts_structure"),
    "transition_style": style_profile.get("transition_style"),
}, ensure_ascii=False)}

Apply this profile as editing taste, not as content to copy. Match rhythm,
segment length, opening hook density, and newsroom balance while preserving
the source video's actual facts and context.
""".rstrip()

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
{style_block}

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


def analyze_with_openai(
    transcript: list[dict[str, Any]],
    style_profile: dict[str, Any] | None = None,
) -> list[dict[str, Any]]:
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
                    style_profile,
                ),
            },
        ],
    )
    content = response.choices[0].message.content or "[]"
    return enrich_highlights_with_skill_scores(
        _parse_json_array(content),
        transcript,
        style_profile,
    )


def fallback_highlights(
    transcript: list[dict[str, Any]],
    duration: float,
    style_profile: dict[str, Any] | None = None,
) -> list[dict[str, Any]]:
    settings = get_settings()
    if _is_fallback_transcript(transcript):
        return fallback_review_highlights(
            duration,
            settings.target_highlight_seconds_min,
            settings.target_highlight_seconds_max,
        )
    return select_highlights_with_skills(
        transcript,
        duration,
        settings.target_highlight_seconds_min,
        settings.target_highlight_seconds_max,
        style_profile,
    )


def _is_fallback_transcript(transcript: list[dict[str, Any]]) -> bool:
    return bool(transcript) and all(
        str(item.get("source") or "") == "fallback_stt" for item in transcript
    )


def fallback_review_highlights(
    duration: float,
    target_min_seconds: float,
    target_max_seconds: float,
    silence_ranges: list[Any] | None = None,
) -> list[dict[str, Any]]:
    duration = max(float(duration or 0), 1.0)
    target_total = _fallback_target_total(
        duration,
        target_min_seconds,
        target_max_seconds,
    )
    clip_count, clip_length = _fallback_clip_shape(duration, target_total)
    audio_activity = _audio_activity_review_highlights(
        duration,
        target_total,
        clip_count,
        clip_length,
        _speech_ranges_from_silence(duration, silence_ranges),
    )
    if audio_activity:
        return audio_activity

    clip_length = min(clip_length, duration)
    available = max(0.0, duration - clip_length)

    highlights: list[dict[str, Any]] = []
    for index in range(clip_count):
        if clip_count == 1:
            start = min(available, max(0.0, duration * 0.4 - clip_length / 2))
        else:
            start = available * (index + 1) / (clip_count + 1)
        end = min(duration, start + clip_length)
        highlights.append(
            {
                "start": round(start, 3),
                "end": round(end, 3),
                "reason": "음성 인식 미설정 상태의 검토용 후보 구간입니다. 실제 하이라이트 판단은 STT 설정 후 가능합니다.",
                "script": "",
                "source": "fallback-review",
                "score": 0.0,
                "tags": ["검토필요", "STT미설정"],
            }
        )
    return highlights


def analyze_highlights(
    transcript: list[dict[str, Any]],
    duration: float,
    style_profile: dict[str, Any] | None = None,
) -> list[dict[str, Any]]:
    settings = get_settings()
    if settings.use_openai_llm and settings.openai_api_key:
        try:
            return analyze_with_openai(transcript, style_profile)
        except Exception:
            return fallback_highlights(transcript, duration, style_profile)
    return fallback_highlights(transcript, duration, style_profile)
