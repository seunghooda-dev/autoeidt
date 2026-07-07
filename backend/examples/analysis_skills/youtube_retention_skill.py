from __future__ import annotations

import re

from app.services.editing_skills import SkillSignal, TranscriptWindow


class YoutubeRetentionSkill:
    name = "youtube_retention"

    def analyze(self, window: TranscriptWindow) -> SkillSignal | None:
        text = window.text
        if re.search(r"(처음|먼저|바로|지금부터|보여드릴게요|비교|차이|전후|결과부터)", text):
            return SkillSignal(
                score=2.6,
                tag="유지율",
                reason="초반 후킹이나 비교 구도가 있어 시청 유지에 유리함",
            )
        if re.search(r"(구독|좋아요|알림|댓글)", text):
            return SkillSignal(
                score=-1.8,
                tag="CTA",
                reason="하이라이트 본문보다 콜투액션 성격이 강함",
            )
        return None


def create_skill() -> YoutubeRetentionSkill:
    return YoutubeRetentionSkill()
