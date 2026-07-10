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
    assert _command_value(command, "-ss") == "8.000000"
    assert "trim=start=2.000000:end=4.000000" in filter_complex
    assert "atrim=start=2.000000:end=4.000000" in filter_complex


def test_legacy_stream_copy_path_is_normalized_to_30p_non_drop(
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

    ffmpeg_service.render_stream_copy(
        Path("C:/media/source_2997_dropframe.mxf"),
        [{"order": 1, "start": 10.0, "end": 12.0, "reason": "test"}],
        tmp_path / "out.mp4",
    )

    command = commands[-1]
    filter_complex = _command_value(command, "-filter_complex")

    assert "-c copy" not in " ".join(command)
    assert "fps=30" in filter_complex
    assert _command_value(command, "-r") == "30"
    assert _command_value(command, "-map_metadata") == "-1"
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
    monkeypatch.setattr(ffmpeg_service, "_audio_stream_count", lambda path: 1)
    monkeypatch.setattr(ffmpeg_service, "_run", fake_run)

    output_path, cached, _, _ = ffmpeg_service.create_preview_proxy(source_path)

    command = commands[-1]
    vf_filter = _command_value(command, "-vf")

    assert cached is False
    assert output_path.exists()
    assert "fps=30" in vf_filter
    assert _command_value(command, "-r") == "30"
    assert _command_value(command, "-write_tmcd") == "0"


def test_preview_proxy_mixes_multistream_audio_for_preview(
    tmp_path: Path,
    monkeypatch,
) -> None:
    source_path = tmp_path / "broadcast_source.mxf"
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
    monkeypatch.setattr(ffmpeg_service, "_audio_stream_count", lambda path: 4)
    monkeypatch.setattr(ffmpeg_service, "_run", fake_run)

    ffmpeg_service.create_preview_proxy(source_path)

    command = commands[-1]
    filter_complex = _command_value(command, "-filter_complex")

    assert "0:a:0" in filter_complex
    assert "0:a:1" in filter_complex
    assert "0:a:2" in filter_complex
    assert "0:a:3" in filter_complex
    assert "amix=inputs=4" in filter_complex
    assert _command_value(command, "-map") == "0:v:0"
    assert command[command.index("-filter_complex") + 2] == "-map"
    assert command[command.index("-filter_complex") + 3] == "[previewa]"


def test_square_render_profile_outputs_30p_square_frame(
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
        tmp_path / "square.mp4",
        aspect_ratio="1:1",
    )

    command = commands[-1]
    filter_complex = _command_value(command, "-filter_complex")

    assert "scale=1080:1080" in filter_complex
    assert "pad=1080:1080" in filter_complex
    assert "fps=30" in filter_complex
