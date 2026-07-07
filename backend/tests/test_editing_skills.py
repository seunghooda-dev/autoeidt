from app.services.editing_skills import select_highlights_with_skills


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
