from app.services.editing_skills import (
    TranscriptWindow,
    score_window,
    select_highlights_with_skills,
)


def test_skill_engine_prioritizes_hook_and_problem_solution() -> None:
    transcript = [
        {"start": 0.0, "end": 15.0, "text": "오늘은 평범한 도입입니다"},
        {
            "start": 15.0,
            "end": 35.0,
            "text": "왜 이 문제가 중요한지 핵심 원인과 실수 3가지를 설명합니다",
        },
        {
            "start": 35.0,
            "end": 55.0,
            "text": "결국 해결 방법은 이 순서대로 적용하는 것입니다",
        },
        {"start": 55.0, "end": 80.0, "text": "마무리 인사입니다"},
    ]

    highlights = select_highlights_with_skills(
        transcript,
        duration=80.0,
        target_min_seconds=30.0,
        target_max_seconds=70.0,
    )

    assert highlights
    joined_tags = {tag for item in highlights for tag in item["tags"]}
    assert {"핵심", "문제해결"} & joined_tags
    assert any(item["score"] > 5 for item in highlights)
    assert any(
        "중요" in item["reason"] or "문제" in item["reason"] or "핵심" in item["reason"]
        for item in highlights
    )


def test_external_skill_path_adds_custom_signal(tmp_path, monkeypatch) -> None:
    skill_file = tmp_path / "custom_skill.py"
    skill_file.write_text(
        """
from app.services.editing_skills import SkillSignal

class CustomSkill:
    name = "custom"

    def analyze(self, window):
        if "오프닝 훅" in window.text:
            return SkillSignal(score=5.0, tag="외부스킬", reason="외부 스킬이 감지한 오프닝 훅")
        return None

def create_skill():
    return CustomSkill()
""",
        encoding="utf-8",
    )
    monkeypatch.setenv("AUTOEDIT_ANALYSIS_SKILL_PATHS", str(tmp_path))

    highlights = select_highlights_with_skills(
        [
            {"start": 0.0, "end": 20.0, "text": "오프닝 훅으로 바로 궁금증을 만듭니다"},
            {"start": 20.0, "end": 45.0, "text": "핵심 문제와 해결 방법을 설명합니다"},
            {"start": 45.0, "end": 70.0, "text": "마무리 인사입니다"},
        ],
        duration=70.0,
        target_min_seconds=20.0,
        target_max_seconds=50.0,
    )

    assert any("외부스킬" in item["tags"] for item in highlights)


def test_skill_engine_penalizes_filler_and_cta() -> None:
    transcript = [
        {
            "start": 0.0,
            "end": 25.0,
            "text": "음 어 이제 약간 뭐랄까 구독 좋아요 알림 부탁드립니다",
        },
        {
            "start": 25.0,
            "end": 55.0,
            "text": "결과부터 보여드리면 가장 중요한 핵심 문제와 해결 방법은 세 가지입니다",
        },
        {"start": 55.0, "end": 80.0, "text": "마무리 인사입니다"},
    ]

    highlights = select_highlights_with_skills(
        transcript,
        duration=80.0,
        target_min_seconds=20.0,
        target_max_seconds=45.0,
    )

    joined_text = " ".join(item["script"] for item in highlights)
    joined_tags = {tag for item in highlights for tag in item["tags"]}
    assert "구독 좋아요" not in joined_text
    assert {"유지율", "핵심", "문제해결"} & joined_tags


def test_news_engine_builds_editorial_sequence_and_avoids_rumor() -> None:
    transcript = [
        {"start": 0.0, "end": 15.0, "text": "오프닝 인사와 구독 좋아요 안내입니다"},
        {
            "start": 15.0,
            "end": 35.0,
            "text": "오늘 오전 서울시청에서 정부는 대형 화재 사고 조사 결과를 발표했습니다",
        },
        {
            "start": 35.0,
            "end": 55.0,
            "text": "소방당국 보고서와 통계 자료에 따르면 피해 규모는 30억 원으로 집계됐습니다",
        },
        {
            "start": 55.0,
            "end": 75.0,
            "text": "일각에서는 아직 확인되지 않은 루머와 추측도 나오고 있습니다",
        },
        {
            "start": 75.0,
            "end": 100.0,
            "text": "인근 주민과 상인들은 안전 우려와 영업 손실 피해가 크다고 말했습니다",
        },
        {
            "start": 100.0,
            "end": 125.0,
            "text": "회사 측은 공식 입장을 내고 사과했으며 경찰은 수사에 착수했습니다",
        },
    ]

    highlights = select_highlights_with_skills(
        transcript,
        duration=125.0,
        target_min_seconds=75.0,
        target_max_seconds=110.0,
    )

    joined_text = " ".join(item["script"] for item in highlights)
    joined_tags = {tag for item in highlights for tag in item["tags"]}
    assert highlights == sorted(highlights, key=lambda item: item["start"])
    assert "구독 좋아요" not in joined_text
    assert "루머" not in joined_text
    assert {"뉴스핵심", "근거", "영향", "대응"} <= joined_tags
    assert all(item["source"] == "editorial-engine" for item in highlights)


def test_verified_fact_skill_rewards_official_sourced_numbers() -> None:
    window = score_window(
        TranscriptWindow(
            start=20.0,
            end=42.0,
            items=[],
            text=(
                "국토교통부 공식 보고서에 따르면 지난달 사고 피해액은 "
                "120억 원으로 집계됐고 장관은 재발 방지 대책을 발표했습니다"
            ),
            source_duration=120.0,
        )
    )

    assert "검증팩트" in window.tags
    assert "근거" in window.tags
    assert "출처확인" in window.tags
    assert any("검증 가능한 뉴스 핵심" in reason for reason in window.reasons)


def test_news_engine_prioritizes_verified_fact_packet() -> None:
    transcript = [
        {
            "start": 0.0,
            "end": 18.0,
            "text": "충격적인 소문이 빠르게 퍼지고 있다는 자극적인 이야기입니다",
        },
        {
            "start": 18.0,
            "end": 38.0,
            "text": "국토교통부 공식 보고서에 따르면 사고 피해액은 120억 원으로 집계됐습니다",
        },
        {
            "start": 38.0,
            "end": 58.0,
            "text": "인근 주민들은 안전 우려와 영업 손실 피해가 크다고 말했습니다",
        },
        {
            "start": 58.0,
            "end": 78.0,
            "text": "정부는 추가 조사와 재발 방지 대책을 발표했습니다",
        },
    ]

    highlights = select_highlights_with_skills(
        transcript,
        duration=78.0,
        target_min_seconds=40.0,
        target_max_seconds=70.0,
    )

    joined_text = " ".join(item["script"] for item in highlights)
    joined_tags = {tag for item in highlights for tag in item["tags"]}
    assert "검증팩트" in joined_tags
    assert "공식 보고서" in joined_text


def test_story_arc_engine_tags_complete_shorts_flow() -> None:
    transcript = [
        {
            "start": 0.0,
            "end": 12.0,
            "text": "결과부터 보면 이번 사고의 핵심은 안전 점검 실패였습니다",
        },
        {
            "start": 12.0,
            "end": 28.0,
            "text": "먼저 배경을 보면 지난달부터 같은 문제가 반복됐습니다",
        },
        {
            "start": 28.0,
            "end": 48.0,
            "text": "당국 공식 보고서와 통계 자료에 따르면 피해 신고는 120건입니다",
        },
        {
            "start": 48.0,
            "end": 68.0,
            "text": "주민들은 안전 우려와 영업 손실 피해가 크다고 말했습니다",
        },
        {
            "start": 68.0,
            "end": 88.0,
            "text": "회사 측은 사과하고 재발 방지 대책과 보상 조치를 발표했습니다",
        },
        {
            "start": 88.0,
            "end": 108.0,
            "text": "일각에서는 아직 확인되지 않은 루머와 추측도 나오고 있습니다",
        },
        {
            "start": 108.0,
            "end": 128.0,
            "text": "구독 좋아요 알림 설정 부탁드립니다",
        },
    ]

    highlights = select_highlights_with_skills(
        transcript,
        duration=128.0,
        target_min_seconds=70.0,
        target_max_seconds=120.0,
    )

    joined_text = " ".join(item["script"] for item in highlights)
    joined_tags = {tag for item in highlights for tag in item["tags"]}
    assert highlights == sorted(highlights, key=lambda item: item["start"])
    assert "루머" not in joined_text
    assert "구독 좋아요" not in joined_text
    assert {"Story:Hook", "Story:Evidence", "Story:Impact", "Story:Resolution"} <= joined_tags
    assert any(item["reason"].startswith("Hook 단계") for item in highlights)
