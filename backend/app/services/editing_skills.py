from __future__ import annotations

import importlib.util
import os
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Protocol


NEWS_STRUCTURE_TAGS = ["뉴스핵심", "근거", "영향", "대응", "출처확인", "시간축", "발언"]
_TOKEN_PATTERN = re.compile(r"[가-힣A-Za-z0-9]{2,}")
_STOPWORDS = {
    "그리고",
    "하지만",
    "그래서",
    "오늘",
    "어제",
    "이번",
    "관련",
    "대한",
    "것으로",
    "있습니다",
    "했습니다",
    "합니다",
    "the",
    "and",
    "that",
    "this",
    "with",
}


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
    source_duration: float = 0.0
    score: float = 0.0
    tags: list[str] = field(default_factory=list)
    reasons: list[str] = field(default_factory=list)
    risks: list[str] = field(default_factory=list)

    @property
    def duration(self) -> float:
        return max(0.001, self.end - self.start)

    @property
    def position_ratio(self) -> float:
        if self.source_duration <= 0:
            return 0.0
        return max(0.0, min(self.start / self.source_duration, 1.0))


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


class RetentionHookSkill:
    name = "retention_hook"

    def analyze(self, window: TranscriptWindow) -> SkillSignal | None:
        if re.search(r"(처음|먼저|바로|지금부터|보여드릴게요|비교|차이|전후|결과부터|딱\s*\d+)", window.text):
            return SkillSignal(
                score=2.5,
                tag="유지율",
                reason="초반 후킹이나 비교 구도가 있어 시청 유지에 유리함",
            )
        return None


class NewsLeadSkill:
    name = "news_lead"

    subject_pattern = re.compile(
        r"(정부|대통령|국회|법원|검찰|경찰|소방|당국|위원회|장관|시장|"
        r"회사|기업|은행|병원|학교|군|대사관|백악관|officials?|agency|court|police)",
        re.I,
    )
    event_pattern = re.compile(
        r"(발표|밝혔|조사|수사|회의|체포|기소|판결|사고|화재|폭발|"
        r"사망|부상|피해|인상|하락|통과|합의|중단|재개|announced|said|reported)",
        re.I,
    )

    def analyze(self, window: TranscriptWindow) -> SkillSignal | None:
        if not self.subject_pattern.search(window.text) or not self.event_pattern.search(window.text):
            return None
        position_bonus = 0.8 if window.position_ratio <= 0.25 else 0.2
        return SkillSignal(
            score=3.3 + position_bonus,
            tag="뉴스핵심",
            reason="뉴스 리드로 쓸 수 있는 주체와 사건이 함께 제시됨",
        )


class AttributionSkill:
    name = "attribution"

    def analyze(self, window: TranscriptWindow) -> SkillSignal | None:
        if not re.search(
            r"(에 따르면|밝혔습니다|밝혔|말했습니다|말했|설명했습니다|전했습니다|"
            r"발표했습니다|발표했|확인했습니다|보도했습니다|according to|said|announced|reported)",
            window.text,
            re.I,
        ):
            return None
        return SkillSignal(score=2.6, tag="출처확인", reason="발언 또는 정보 출처가 명시됨")


class EvidenceSkill:
    name = "evidence"

    def analyze(self, window: TranscriptWindow) -> SkillSignal | None:
        matches = re.findall(
            r"(자료|수치|통계|보고서|조사|집계|분석|데이터|문서|녹취|CCTV|영상|"
            r"사진|기록|근거|확인|report|data|survey|document|evidence)",
            window.text,
            re.I,
        )
        if not matches:
            return None
        return SkillSignal(
            score=2.8 + min(len(matches), 3) * 0.35,
            tag="근거",
            reason="자료와 근거가 있어 보도 신뢰도를 높임",
        )


class ImpactSkill:
    name = "impact"

    def analyze(self, window: TranscriptWindow) -> SkillSignal | None:
        if not re.search(
            r"(피해|영향|사망|부상|손실|위험|우려|논란|시민|주민|소비자|이용자|"
            r"환자|학생|노동자|시장|경제|안전|impact|damage|victims|residents)",
            window.text,
            re.I,
        ):
            return None
        return SkillSignal(score=2.7, tag="영향", reason="시청자가 알아야 할 피해와 영향이 설명됨")


class ResponseSkill:
    name = "response"

    def analyze(self, window: TranscriptWindow) -> SkillSignal | None:
        if not re.search(
            r"(반박|해명|입장|대응|조치|사과|대책|검토|고발|소송|처벌|조사에 착수|"
            r"수사에 착수|denied|response|apologized|measures)",
            window.text,
            re.I,
        ):
            return None
        return SkillSignal(score=2.5, tag="대응", reason="공식 대응이나 반론이 포함돼 균형을 맞춤")


class ChronologySkill:
    name = "chronology"

    def analyze(self, window: TranscriptWindow) -> SkillSignal | None:
        if not re.search(
            r"(오늘|어제|그제|지난\s*\d*|지난달|지난해|오전|오후|현지\s*시간|"
            r"\d{1,2}월\s*\d{1,2}일|\d{4}년|이후|당시|before|after|today|yesterday)",
            window.text,
            re.I,
        ):
            return None
        return SkillSignal(score=1.8, tag="시간축", reason="사건의 시간 흐름을 이해하는 데 필요함")


class QuoteSkill:
    name = "quote"

    def analyze(self, window: TranscriptWindow) -> SkillSignal | None:
        if not re.search(r"(라고\s*말|라고\s*밝|인터뷰|발언|증언|quoted|interview)", window.text, re.I):
            return None
        return SkillSignal(score=1.9, tag="발언", reason="직접 발언이나 인터뷰성 맥락이 포함됨")


class TransitionSkill:
    name = "transition"

    def analyze(self, window: TranscriptWindow) -> SkillSignal | None:
        if re.search(r"(그런데|하지만|반대로|그래서|결국|즉|다만|문제는|핵심은)", window.text):
            return SkillSignal(score=1.7, tag="전환", reason="논리 전환점이라 앞뒤 맥락을 압축하기 좋음")
        return None


class FillerWordSkill:
    name = "filler_word"

    def analyze(self, window: TranscriptWindow) -> SkillSignal | None:
        matches = re.findall(
            r"(\b음+\b|\b어+\b|\b아+\b|그니까|그러니까|뭐랄까|약간|이제|사실\s*은?|you know|um+|uh+)",
            window.text,
            re.I,
        )
        if len(matches) >= 5:
            return SkillSignal(
                score=-2.4,
                tag="말버릇",
                reason="반복 말버릇이 많아 하이라이트 밀도가 낮음",
            )
        if len(matches) >= 2:
            return SkillSignal(
                score=-1.0,
                tag="말버릇",
                reason="말버릇이 있어 짧은 편집에서는 우선순위가 낮음",
            )
        return None


class CallToActionSkill:
    name = "call_to_action"

    def analyze(self, window: TranscriptWindow) -> SkillSignal | None:
        if re.search(r"(구독|좋아요|알림|댓글|팔로우|subscribe|like and)", window.text, re.I):
            return SkillSignal(
                score=-1.8,
                tag="CTA",
                reason="하이라이트 본문보다 콜투액션 성격이 강함",
            )
        return None


class SpeculationRiskSkill:
    name = "speculation_risk"

    def analyze(self, window: TranscriptWindow) -> SkillSignal | None:
        if not re.search(
            r"(루머|카더라|추정됩니다|추측|아마도|미확인|확인되지 않았|일각에서는|"
            r"떠돌고|rumor|unconfirmed|allegedly|speculation)",
            window.text,
            re.I,
        ):
            return None
        return SkillSignal(
            score=-3.0,
            tag="미확인",
            reason="확인되지 않은 추정성 표현이 있어 뉴스 편집 우선순위가 낮음",
        )


class ContextRiskSkill:
    name = "context_risk"

    def analyze(self, window: TranscriptWindow) -> SkillSignal | None:
        text = window.text.strip()
        if not re.match(r"^(그래서|그런데|하지만|다만|이런|그런|이\s|그\s|또\s)", text):
            return None
        if any(tag in window.tags for tag in ["뉴스핵심", "출처확인", "근거"]):
            return None
        return SkillSignal(
            score=-1.1,
            tag="맥락부족",
            reason="앞 문맥 없이 시작하면 단독 클립 이해도가 낮음",
        )


BUILT_IN_SKILLS: list[EditingSkill] = [
    KeywordSkill(),
    QuestionSkill(),
    NumberSpecificitySkill(),
    InformationDensitySkill(),
    EmotionSkill(),
    RetentionHookSkill(),
    NewsLeadSkill(),
    AttributionSkill(),
    EvidenceSkill(),
    ImpactSkill(),
    ResponseSkill(),
    ChronologySkill(),
    QuoteSkill(),
    TransitionSkill(),
    FillerWordSkill(),
    CallToActionSkill(),
    SpeculationRiskSkill(),
    ContextRiskSkill(),
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
    source_duration: float = 0.0,
) -> list[TranscriptWindow]:
    windows: list[TranscriptWindow] = []
    if not transcript:
        return windows

    targets = [min_seconds, ideal_seconds, max_seconds]
    for start_index, start_item in enumerate(transcript):
        start = float(start_item.get("start", 0.0))
        items: list[dict[str, Any]] = []
        target_index = 0
        emitted = False
        for item in transcript[start_index:]:
            items.append(item)
            end = float(item.get("end", start))
            span = end - start
            while target_index < len(targets) and span >= targets[target_index]:
                text = " ".join(str(part.get("text", "")) for part in items).strip()
                if text:
                    windows.append(
                        TranscriptWindow(
                            start=start,
                            end=end,
                            items=items.copy(),
                            text=text,
                            source_duration=source_duration,
                        )
                    )
                    emitted = True
                target_index += 1
            if span >= max_seconds:
                break
            if item is transcript[-1] and not emitted and span >= min_seconds:
                text = " ".join(str(part.get("text", "")) for part in items).strip()
                if text:
                    windows.append(
                        TranscriptWindow(
                            start=start,
                            end=end,
                            items=items.copy(),
                            text=text,
                            source_duration=source_duration,
                        )
                    )
                break
    return windows


def score_window(
    window: TranscriptWindow,
    skills: list[EditingSkill] | None = None,
    style_profile: dict[str, Any] | None = None,
) -> TranscriptWindow:
    active_skills = skills or [*BUILT_IN_SKILLS, *load_external_skills()]
    base_score = min(window.duration / 12.0, 3.5)
    if 20.0 <= window.duration <= 58.0:
        base_score += 0.5
    if len(window.items) >= 2:
        base_score += 0.25
    window.score = base_score
    window.tags = []
    window.reasons = []
    window.risks = []
    for skill in active_skills:
        signal = skill.analyze(window)
        if signal is None:
            continue
        window.score += signal.score
        if signal.score < 0:
            if signal.tag not in window.risks:
                window.risks.append(signal.tag)
            continue
        if signal.tag not in window.tags:
            window.tags.append(signal.tag)
        if signal.reason not in window.reasons:
            window.reasons.append(signal.reason)

    _apply_style_profile_score(window, style_profile)

    if not window.tags:
        window.tags.append("문맥")
    if not window.reasons:
        window.reasons.append("문맥이 이어지는 후보 구간")
    return window


def _style_float(
    style_profile: dict[str, Any] | None,
    key: str,
    fallback: float,
) -> float:
    if not style_profile:
        return fallback
    try:
        return float(style_profile.get(key, fallback))
    except (TypeError, ValueError):
        return fallback


def _style_weight(
    style_profile: dict[str, Any] | None,
    key: str,
    fallback: float,
) -> float:
    weights = style_profile.get("scoring_weights", {}) if style_profile else {}
    try:
        return float(weights.get(key, fallback))
    except (TypeError, ValueError, AttributeError):
        return fallback


def _apply_style_profile_score(
    window: TranscriptWindow,
    style_profile: dict[str, Any] | None,
) -> None:
    if not style_profile:
        return

    target_min = _style_float(style_profile, "target_segment_seconds_min", 18.0)
    target_ideal = _style_float(style_profile, "target_segment_seconds_ideal", 36.0)
    target_max = _style_float(style_profile, "target_segment_seconds_max", 52.0)
    hook_window = _style_float(style_profile, "hook_window_seconds", 15.0)
    style_weight = _style_weight(style_profile, "style_duration", 1.0)
    hook_weight = _style_weight(style_profile, "hook", 1.0)
    info_weight = _style_weight(style_profile, "information_density", 1.0)
    news_weight = _style_weight(style_profile, "news_structure", 1.0)

    if target_min <= window.duration <= target_max:
        distance = abs(window.duration - target_ideal) / max(target_ideal, 1.0)
        window.score += max(0.0, 1.4 - distance) * style_weight
        if "레퍼런스길이" not in window.tags:
            window.tags.append("레퍼런스길이")
        window.reasons.append("레퍼런스 영상의 컷 길이와 유사함")
    else:
        window.score -= 0.8 * style_weight
        if "길이불일치" not in window.risks:
            window.risks.append("길이불일치")

    if window.start <= hook_window:
        window.score += 0.9 * hook_weight
        if "레퍼런스훅" not in window.tags:
            window.tags.append("레퍼런스훅")
        window.reasons.append("레퍼런스 스타일의 초반 후킹 구간에 해당")

    if any(tag in window.tags for tag in ["고밀도", "정보밀도", "구체성", "근거"]):
        window.score += 0.45 * info_weight

    if bool(style_profile.get("prefer_news_structure", False)) and any(
        tag in window.tags for tag in NEWS_STRUCTURE_TAGS
    ):
        window.score += 0.55 * news_weight

    pace = str(style_profile.get("pace", "balanced"))
    if pace in {"very_fast", "fast"} and window.duration > target_max:
        window.score -= 1.2
    if pace == "slow" and window.duration < target_min:
        window.score -= 0.8


def text_tokens(text: str) -> set[str]:
    return {
        token.lower()
        for token in _TOKEN_PATTERN.findall(text)
        if token.lower() not in _STOPWORDS
    }


def text_similarity(a: TranscriptWindow, b: TranscriptWindow) -> float:
    left = text_tokens(a.text)
    right = text_tokens(b.text)
    if not left or not right:
        return 0.0
    return len(left & right) / len(left | right)


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


def window_source(window: TranscriptWindow) -> str:
    return "editorial-engine" if any(tag in window.tags for tag in NEWS_STRUCTURE_TAGS) else "skill-engine"


def can_add_window(
    candidate: TranscriptWindow,
    selected: list[TranscriptWindow],
    total: float,
    effective_max_seconds: float,
) -> bool:
    if selected and total + candidate.duration > effective_max_seconds:
        return False
    for chosen in selected:
        if overlap_ratio(candidate, chosen) > 0.35:
            return False
        if text_similarity(candidate, chosen) > 0.62:
            return False
    return True


def choose_best_for_tag(
    candidates: list[TranscriptWindow],
    selected: list[TranscriptWindow],
    total: float,
    effective_max_seconds: float,
    tag: str,
) -> TranscriptWindow | None:
    tagged = [
        candidate
        for candidate in candidates
        if tag in candidate.tags and can_add_window(candidate, selected, total, effective_max_seconds)
    ]
    if not tagged:
        return None

    def editorial_rank(window: TranscriptWindow) -> float:
        early_bonus = 1.0 - window.position_ratio if tag == "뉴스핵심" else 0.0
        risk_penalty = len(window.risks) * 4.0
        return window.score + early_bonus + min(window.duration / 40.0, 1.0) - risk_penalty

    return max(tagged, key=editorial_rank)


def select_highlights_with_skills(
    transcript: list[dict[str, Any]],
    duration: float,
    target_min_seconds: float,
    target_max_seconds: float,
    style_profile: dict[str, Any] | None = None,
) -> list[dict[str, Any]]:
    effective_min_seconds = min(target_min_seconds, max(20.0, duration * 0.35))
    effective_max_seconds = min(
        target_max_seconds,
        max(effective_min_seconds, duration * 0.85),
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
    window_min = _style_float(style_profile, "target_segment_seconds_min", 18.0)
    window_ideal = _style_float(style_profile, "target_segment_seconds_ideal", 42.0)
    window_max = _style_float(style_profile, "target_segment_seconds_max", 58.0)
    candidates = [
        score_window(window, skills, style_profile)
        for window in build_windows(
            transcript,
            min_seconds=window_min,
            ideal_seconds=window_ideal,
            max_seconds=window_max,
            source_duration=duration,
        )
    ]
    if not candidates:
        candidates = [
            score_window(
                TranscriptWindow(
                    start=float(transcript[0].get("start", 0.0)),
                    end=float(transcript[-1].get("end", duration or 0.0)),
                    items=transcript,
                    text=" ".join(str(item.get("text", "")) for item in transcript),
                    source_duration=duration,
                ),
                skills,
                style_profile,
            )
        ]

    selected: list[TranscriptWindow] = []
    total = 0.0
    for tag in NEWS_STRUCTURE_TAGS[:4]:
        candidate = choose_best_for_tag(
            candidates,
            selected,
            total,
            effective_max_seconds,
            tag,
        )
        if candidate is None:
            continue
        selected.append(candidate)
        total += candidate.duration

    for candidate in sorted(candidates, key=lambda item: item.score / item.duration, reverse=True):
        if selected and total >= effective_min_seconds:
            break
        if not can_add_window(candidate, selected, total, effective_max_seconds):
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
            "source": window_source(item),
            "score": round(item.score, 2),
            "tags": item.tags,
        }
        for item in selected
    ]


def enrich_highlights_with_skill_scores(
    highlights: list[dict[str, Any]],
    transcript: list[dict[str, Any]],
    style_profile: dict[str, Any] | None = None,
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
            style_profile,
        )
        item = {**highlight}
        item.setdefault("script", script_preview(window))
        item["score"] = round(max(float(item.get("score", 0.0)), window.score), 2)
        existing_tags = [str(tag) for tag in item.get("tags", []) if str(tag).strip()]
        item["tags"] = list(dict.fromkeys([*existing_tags, *window.tags]))[:6]
        if not str(item.get("reason", "")).strip():
            item["reason"] = reason_for_window(window)
        item.setdefault("source", "editorial-llm" if any(tag in window.tags for tag in NEWS_STRUCTURE_TAGS) else "llm")
        enriched.append(item)
    return enriched
