from pathlib import Path

from app import tasks
from app.services.ffmpeg_service import SilenceRange


def test_scene_detection_failure_becomes_analysis_warning(monkeypatch) -> None:
    def fail_scene_detection(*args, **kwargs):
        raise RuntimeError("ffmpeg scene failed")

    monkeypatch.setattr(tasks, "detect_scene_changes", fail_scene_detection)
    warnings: list[str] = []

    points = tasks._detect_scene_points_for_analysis(
        Path("source.mxf"),
        0.35,
        warnings,
    )

    assert points == []
    assert warnings
    assert "화면 전환 탐지" in warnings[0]
    assert "ffmpeg scene failed" in warnings[0]


def test_motion_protection_failure_keeps_scene_protected_silences(monkeypatch) -> None:
    def fail_motion_protection(*args, **kwargs):
        raise RuntimeError("opencv motion failed")

    monkeypatch.setattr(tasks, "build_protected_silences", fail_motion_protection)
    warnings: list[str] = []
    silences = [
        SilenceRange(start=10.0, end=12.0, duration=2.0),
        SilenceRange(start=30.0, end=34.0, duration=4.0),
    ]

    protected = tasks._build_protected_silences_for_analysis(
        Path("source.mxf"),
        silences,
        [11.0],
        warnings,
    )

    assert protected == [silences[0]]
    assert warnings
    assert "시각적 모션 보호 검사" in warnings[0]
    assert "opencv motion failed" in warnings[0]
