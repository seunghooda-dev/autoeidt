import subprocess
from pathlib import Path

from app.services import ffmpeg_service


class _FakeSettings:
    def __init__(self, data_dir: Path) -> None:
        self.data_dir = data_dir
        self.prefer_gpu_encoding = False
        self.preview_proxy_seconds = 180


def _command_value(command: list[str], option: str) -> str:
    return command[command.index(option) + 1]


def test_render_reencode_forces_30p_non_drop_output(
    tmp_path: Path,
    monkeypatch,
) -> None:
    commands: list[list[str]] = []

    def fake_run(
        command: list[str],
        timeout: int | None = None,
    ) -> subprocess.CompletedProcess[str]:
        commands.append(command)
        return subprocess.CompletedProcess(command, 0, "", "")

    monkeypatch.setattr(ffmpeg_service, "get_settings", lambda: _FakeSettings(tmp_path))
    monkeypatch.setattr(ffmpeg_service, "_audio_stream_count", lambda path: 2)
    monkeypatch.setattr(ffmpeg_service, "_run", fake_run)

    ffmpeg_service.render_highlights_reencoded(
        Path("C:/media/source.mxf"),
        [{"order": 1, "start": 10.0, "end": 12.0, "reason": "test"}],
        tmp_path / "out.mp4",
    )

    command = commands[-1]
    filter_complex = _command_value(command, "-filter_complex")

    assert "fps=30" in filter_complex
    assert _command_value(command, "-r") == "30"
    assert _command_value(command, "-map_metadata") == "-1"
    assert _command_value(command, "-map_chapters") == "-1"
    assert _command_value(command, "-write_tmcd") == "0"


def test_preview_proxy_forces_30p_non_drop_output(
    tmp_path: Path,
    monkeypatch,
) -> None:
    source_path = tmp_path / "source.mxf"
    source_path.write_bytes(b"source")
    commands: list[list[str]] = []

    def fake_run(
        command: list[str],
        timeout: int | None = None,
    ) -> subprocess.CompletedProcess[str]:
        commands.append(command)
        Path(command[-1]).write_bytes(b"proxy")
        return subprocess.CompletedProcess(command, 0, "", "")

    monkeypatch.setattr(ffmpeg_service, "get_settings", lambda: _FakeSettings(tmp_path))
    monkeypatch.setattr(ffmpeg_service, "_run", fake_run)

    output_path, cached, _, _ = ffmpeg_service.create_preview_proxy(source_path)

    command = commands[-1]
    vf_filter = _command_value(command, "-vf")

    assert cached is False
    assert output_path.exists()
    assert "fps=30" in vf_filter
    assert _command_value(command, "-r") == "30"
    assert _command_value(command, "-write_tmcd") == "0"
