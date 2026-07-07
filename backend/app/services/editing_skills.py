from __future__ import annotations

import importlib.util
import os
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Protocol


@dataclass(frozen=True)
class SkillSignal:
    score: float
    tag: str
    reason: str


@dataclass
class TranscriptWindow:
    start: float
    end: float
    items: list[dict[str, Any]]
    text: str
    score: float = 0.0
    tags: list[str] = field(default_factory=list)
    reasons: list[str] = field(default_factory=list)

    @property
    def duration(self) -> float:
        return max(0.001, self.end - self.start)


class EditingSkill(Protocol):
    name: str

    def analyze(self, window: TranscriptWindow) -> SkillSignal | None:
        ...


class KeywordSkill:
    name = "keyword"

    groups = {
        "핵심": {
            "weight": 3.4,
            "words": ["중요", "핵심", "결론", "정리", "요약", "포인트", "핵심은"],
            "reason": "핵심 내용이나 결론을 직접 언급",
        },
        "문제해결": {
            "weight": 3.0,
            "words": ["문제", "해결", "방법", "실수", "주의", "개선", "원인"],
            "reason": "문제와 해결 흐름이 명확함",
        },
        "호기심": {
            "weight": 2.8,
            "words": ["비밀", "반전", "놀라운", "왜", "어떻게", "진짜", "사실은"],
            "reason": "시청자의 호기심을 유발하는 표현 포함",
        },
        "강조": {
            "weight": 2.4,
            "words": ["반드시", "꼭", "절대", "가장", "최고", "최악", "완전"],
            "reason": "강조 표현으로 주목도가 높음",
        },
        "english-key": {
            "weight": 2.5,
            "words": ["important", "key", "why", "how", "secret", "mistake", "best"],
            "reason": "핵심 의미를 가진 영어 표현 포함",
        },
    }

    def analyze(self, window: TranscriptWindow) -> SkillSignal | None:
        lowered = window.text.lower()
        best: SkillSignal | None = None
        for tag, spec in self.groups.items():
            matches = [word for word in spec["words"] if word.lower() in lowered]
            if not matches:
                continue
            score = float(spec["weight"]) + min(len(matches), 4) * 0.4
            signal = SkillSignal(score=score, tag=tag, reason=str(spec["reason"]))
            if best is None or signal.score > best.score:
                best = signal
        return best


class QuestionSkill:
    name = "question"

    def analyze(self, window: TranscriptWindow) -> SkillSignal | None:
        text = window.text
        question_mark_count = text.count("?") + text.count("？")
        question_words = re.findall(r"(왜|어떻게|무엇|뭐가|어떤|언제|where|why|how|what)", text, re.I)
        if not question_mark_count and not question_words:
            return None
        score = 2.1 + question_mark_count * 0.5 + min(len(question_words), 4) * 0.35
        return SkillSignal(score=score, tag="질문", reason="질문형 문맥으로 다음 내용을 궁금하게 만듦")


class NumberSpecificitySkill:
    name = "number_specificity"

    def analyze(self, window: TranscriptWindow) -> SkillSignal | None:
        matches = re.findall(r"(\d+(?:\.\d+)?\s*(?:%|퍼센트|초|분|개|가지|원|달러)?|첫\s*번째|두\s*번째|세\s*번째)", window.text)
        if not matches:
            return None
        score = 1.8 + min(len(matches), 5) * 0.45
        return SkillSignal(score=score, tag="구체성", reason="숫자와 구체 표현이 있어 정보 신뢰도가 높음")


class InformationDensitySkill:
    name = "information_density"

    def analyze(self, window: TranscriptWindow) -> SkillSignal | None:
        compact_text = re.sub(r"\s+", "", window.text)
        density = len(compact_text) / window.duration
        if density < 2.0:
            return SkillSignal(score=-1.4, tag="저밀도", reason="말의 정보 밀도가 낮아 우선순위가 낮음")
        if density > 9.5:
            return SkillSignal(score=2.2, tag="고밀도", reason="짧은 시간에 정보가 많이 담김")
        if density > 5.5:
            return SkillSignal(score=1.4, tag="정보밀도", reason="말의 밀도가 안정적으로 높음")
        return None


class EmotionSkill:
    name = "emotion"

    patterns = [
        r"대박|와우|진짜|미쳤|놀랍|웃기|행복|불안|화나|충격|레전드",
        r"wow|crazy|amazing|shocking|funny|love|hate",
    ]

    def analyze(self, window: TranscriptWindow) -> SkillSignal | None:
        if not any(re.search(pattern, window.text, re.I) for pattern in self.patterns):
            return None
        return SkillSignal(score=2.2, tag="감정", reason="감정 반응이 있어 시청 유지에 유리함")


class TransitionSkill:
    name = "transition"

    def analyze(self, window: TranscriptWindow) -> SkillSignal | None:
        if re.search(r"(그런데|하지만|반대로|그래서|결국|즉|다만|문제는|핵심은)", window.text):
            return SkillSignal(score=1.7, tag="전환", reason="논리 전환점이라 앞뒤 맥락을 압축하기 좋음")
        return None


BUILT_IN_SKILLS: list[EditingSkill] = [
    KeywordSkill(),
    QuestionSkill(),
    NumberSpecificitySkill(),
    InformationDensitySkill(),
    EmotionSkill(),
    TransitionSkill(),
]


def _load_external_skill(path: Path) -> EditingSkill | None:
    spec = importlib.util.spec_from_file_location(f"autoedit_skill_{path.stem}", path)
    if spec is None or spec.loader is None:
        return None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    skill = getattr(module, "SKILL", None)
    if skill is not None and hasattr(skill, "analyze"):
        return skill
    factory = getattr(module, "create_skill", None)
    if callable(factory):
        created = factory()
        if hasattr(created, "analyze"):
            return created
    return None


def load_external_skills() -> list[EditingSkill]:
    paths = os.getenv("AUTOEDIT_ANALYSIS_SKILL_PATHS", "")
    skills: list[EditingSkill] = []
    for raw_path in paths.split(os.pathsep):
        if not raw_path.strip():
            continue
        root = Path(raw_path).expanduser()
        candidates = [root] if root.is_file() else sorted(root.glob("*.py"))
        for candidate in candidates:
            try:
                skill = _load_external_skill(candidate)
            except Exception:
                continue
            if skill is not None:
                skills.append(skill)
    return skills


def build_windows(
    transcript: list[dict[str, Any]],
    min_seconds: float = 18.0,
    ideal_seconds: float = 42.0,
    max_seconds: float = 58.0,
) -> list[TranscriptWindow]:
    windows: list[TranscriptWindow] = []
    if not transcript:
        return windows

    for start_index, start_item in enumerate(transcript):
        start = float(start_item.get("start", 0.0))
        items: list[dict[str, Any]] = []
        for item in transcript[start_index:]:
            items.append(item)
            end = float(item.get("end", start))
            span = end - start
            if span < min_seconds:
                continue
            if span > max_seconds:
                break
            if span >= ideal_seconds or item is transcript[-1]:
                text = " ".join(str(part.get("text", "")) for part in items).strip()
                if text:
                    windows.append(TranscriptWindow(start=start, end=end, items=items.copy(), text=text))
                break
    return windows


def score_window(
    window: TranscriptWindow,
    skills: list[EditingSkill] | None = None,
) -> TranscriptWindow:
    active_skills = skills or [*BUILT_IN_SKILLS, *load_external_skills()]
    base_score = min(window.duration / 12.0, 3.5)
    window.score = base_score
    window.tags = []
    window.reasons = []
    for skill in active_skills:
        signal = skill.analyze(window)
        if signal is None:
            continue
        window.score += signal.score
        if signal.score < 0:
            continue
        if signal.tag not in window.tags:
            window.tags.append(signal.tag)
        if signal.reason not in window.reasons:
            window.reasons.append(signal.reason)

    if not window.tags:
        window.tags.append("문맥")
    if not window.reasons:
        window.reasons.append("문맥이 이어지는 후보 구간")
    return window


def overlap_ratio(a: TranscriptWindow, b: TranscriptWindow) -> float:
    overlap = max(0.0, min(a.end, b.end) - max(a.start, b.start))
    shortest = min(a.duration, b.duration)
    return 0.0 if shortest <= 0 else overlap / shortest


def script_preview(window: TranscriptWindow, max_length: int = 120) -> str:
    text = re.sub(r"\s+", " ", window.text).strip()
    if len(text) <= max_length:
        return text
    return f"{text[: max_length - 1].rstrip()}…"


def reason_for_window(window: TranscriptWindow) -> str:
    main = window.reasons[:2]
    tags = ", ".join(window.tags[:4])
    detail = " / ".join(main)
    return f"{detail} ({tags})"


def select_highlights_with_skills(
    transcript: list[dict[str, Any]],
    duration: float,
    target_min_seconds: float,
    target_max_seconds: float,
) -> list[dict[str, Any]]:
    effective_min_seconds = min(target_min_seconds, max(20.0, duration * 0.35))
    effective_max_seconds = min(
        target_max_seconds,
        max(effective_min_seconds, duration * 0.68),
    )
    if not transcript:
        end = min(duration or 60.0, 45.0)
        return [
            {
                "start": 0.0,
                "end": end,
                "reason": "스크립트가 없어 초반 핵심 구간을 기본 선택",
                "score": 0.0,
                "tags": ["fallback"],
                "script": "",
                "source": "skill-fallback",
            }
        ]

    skills = [*BUILT_IN_SKILLS, *load_external_skills()]
    candidates = [score_window(window, skills) for window in build_windows(transcript)]
    if not candidates:
        candidates = [
            score_window(
                TranscriptWindow(
                    start=float(transcript[0].get("start", 0.0)),
                    end=float(transcript[-1].get("end", duration or 0.0)),
                    items=transcript,
                    text=" ".join(str(item.get("text", "")) for item in transcript),
                ),
                skills,
            )
        ]

    selected: list[TranscriptWindow] = []
    total = 0.0
    for candidate in sorted(candidates, key=lambda item: item.score / item.duration, reverse=True):
        if selected and total >= effective_min_seconds:
            break
        if any(overlap_ratio(candidate, chosen) > 0.35 for chosen in selected):
            continue
        if selected and total + candidate.duration > effective_max_seconds:
            continue
        selected.append(candidate)
        total += candidate.duration

    if not selected:
        selected = [max(candidates, key=lambda item: item.score)]

    selected.sort(key=lambda item: item.start)
    return [
        {
            "start": round(item.start, 3),
            "end": round(item.end, 3),
            "reason": reason_for_window(item),
            "script": script_preview(item),
            "source": "skill-engine",
            "score": round(item.score, 2),
            "tags": item.tags,
        }
        for item in selected
    ]


def enrich_highlights_with_skill_scores(
    highlights: list[dict[str, Any]],
    transcript: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    enriched: list[dict[str, Any]] = []
    skills = [*BUILT_IN_SKILLS, *load_external_skills()]
    for highlight in highlights:
        start = float(highlight.get("start", 0.0))
        end = float(highlight.get("end", start))
        items = [
            item
            for item in transcript
            if max(start, float(item.get("start", 0.0))) < min(end, float(item.get("end", 0.0)))
        ]
        text = " ".join(str(item.get("text", "")) for item in items).strip()
        window = score_window(
            TranscriptWindow(start=start, end=end, items=items, text=text),
            skills,
        )
        item = {**highlight}
        item.setdefault("script", script_preview(window))
        item["score"] = round(float(item.get("score", window.score)), 2)
        item["tags"] = list(item.get("tags") or window.tags)
        if not str(item.get("reason", "")).strip():
            item["reason"] = reason_for_window(window)
        item.setdefault("source", "llm")
        enriched.append(item)
    return enriched
