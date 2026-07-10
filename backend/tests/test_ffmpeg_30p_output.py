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


def test_preview_proxy_routes_first_two_program_audio_streams(
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
    assert "0:a:2" not in filter_complex
    assert "0:a:3" not in filter_complex
    assert "amerge=inputs=2" in filter_complex
    assert _command_value(command, "-map") == "0:v:0"
    assert command[command.index("-filter_complex") + 2] == "-map"
    assert command[command.index("-filter_complex") + 3] == "[previewa]"


def test_preview_proxy_routes_first_two_interleaved_channels() -> None:
    args = ffmpeg_service._preview_audio_output_args([8])

    filter_complex = _command_value(args, "-filter_complex")
    assert "[0:a:0]" in filter_complex
    assert "pan=stereo|c0=c0|c1=c1" in filter_complex


def test_analysis_audio_routes_first_two_separate_program_streams(
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

    monkeypatch.setattr(ffmpeg_service, "_audio_stream_count", lambda path: 8)
    monkeypatch.setattr(
        ffmpeg_service,
        "_audio_channel_counts",
        lambda path, count: [1] * 8,
    )
    monkeypatch.setattr(ffmpeg_service, "_run", fake_run)

    ffmpeg_service.extract_audio(
        Path("C:/media/broadcast_source.mxf"),
        tmp_path / "analysis.wav",
    )

    filter_complex = _command_value(commands[-1], "-filter_complex")
    assert "0:a:0" in filter_complex
    assert "0:a:1" in filter_complex
    assert "0:a:2" not in filter_complex
    assert "amix=inputs=2" in filter_complex


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


def test_audio_routing_maps_interleaved_source_channels() -> None:
    filters, source = ffmpeg_service._segment_audio_source_filters(
        index=0,
        audio_start=0,
        audio_end=5,
        video_duration=5,
        volume=1,
        channel_1_enabled=True,
        channel_2_enabled=True,
        audio_channel_counts=[8],
        source_channel_left=7,
        source_channel_right=8,
    )

    filter_text = ";".join(filters)
    assert source == "[asrc0]"
    assert "[0:a:0]" in filter_text
    assert "pan=stereo|c0=c6|c1=c7" in filter_text


def test_audio_routing_maps_separate_mono_streams() -> None:
    filters, source = ffmpeg_service._segment_audio_source_filters(
        index=0,
        audio_start=0,
        audio_end=5,
        video_duration=5,
        volume=1,
        channel_1_enabled=True,
        channel_2_enabled=True,
        audio_channel_counts=[1] * 8,
        source_channel_left=7,
        source_channel_right=8,
    )

    filter_text = ";".join(filters)
    assert source == "[asrc0]"
    assert "[0:a:6]" in filter_text
    assert "[0:a:7]" in filter_text
    assert "amerge=inputs=2" in filter_text


def test_render_uses_selected_broadcast_loudness_target(
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
    monkeypatch.setattr(ffmpeg_service, "_audio_stream_count", lambda path: 1)
    monkeypatch.setattr(ffmpeg_service, "_audio_channel_counts", lambda path, count: [2])
    monkeypatch.setattr(ffmpeg_service, "_run", fake_run)

    ffmpeg_service.render_highlights_reencoded(
        Path("C:/media/source.mxf"),
        [
            {
                "order": 1,
                "start": 0,
                "end": 5,
                "reason": "loudness",
                "audio_normalize": True,
                "audio_loudness_target": -24,
            }
        ],
        tmp_path / "broadcast.mp4",
    )

    filter_complex = _command_value(commands[-1], "-filter_complex")
    assert "loudnorm=I=-24.0:TP=-2.0:LRA=11" in filter_complex
