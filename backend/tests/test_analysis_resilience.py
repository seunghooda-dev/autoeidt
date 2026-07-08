from pathlib import Path

from app import tasks
from app.services.ffmpeg_service import SilenceRange


def test_waveform_failure_becomes_analysis_warning(monkeypatch) -> None:
    def fail_waveform(*args, **kwargs):
        raise RuntimeError("waveform failed")

    monkeypatch.setattr(tasks, "generate_waveform", fail_waveform)
    warnings: list[str] = []

    waveform = tasks._generate_waveform_for_analysis(
        Path("audio.wav"),
        warnings,
    )

    assert waveform == []
    assert warnings
    assert "오디오 파형 생성" in warnings[0]
    assert "waveform failed" in warnings[0]


def test_silence_detection_failure_becomes_analysis_warning(monkeypatch) -> None:
    def fail_silence_detection(*args, **kwargs):
        raise RuntimeError("silence failed")

    monkeypatch.setattr(tasks, "detect_silence", fail_silence_detection)
    warnings: list[str] = []

    silences = tasks._detect_silences_for_analysis(
        Path("audio.wav"),
        "-35dB",
        0.8,
        warnings,
    )

    assert silences == []
    assert warnings
    assert "침묵 구간 탐지" in warnings[0]
    assert "silence failed" in warnings[0]


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
