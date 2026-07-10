from concurrent.futures import ThreadPoolExecutor
import json
import os
import subprocess
import time
from pathlib import Path

from app.services import ffmpeg_service


class _FakeSettings:
    def __init__(self, data_dir: Path) -> None:
        self.data_dir = data_dir
        self.prefer_gpu_encoding = False
        self.preview_proxy_seconds = 8


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
    assert vf_filter.startswith("fps=30,scale=-2:540")
    assert _command_value(command, "-r") == "30"
    assert _command_value(command, "-t") == "8.000"
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


def test_duplicate_preview_requests_share_one_ffmpeg_generation(
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
        time.sleep(0.05)
        Path(command[-1]).write_bytes(b"proxy")
        return subprocess.CompletedProcess(command, 0, "", "")

    monkeypatch.setattr(ffmpeg_service, "get_settings", lambda: _FakeSettings(tmp_path))
    monkeypatch.setattr(ffmpeg_service, "_audio_stream_count", lambda path: 2)
    monkeypatch.setattr(
        ffmpeg_service,
        "_audio_channel_counts",
        lambda path, count: [1, 1],
    )
    monkeypatch.setattr(ffmpeg_service, "_run", fake_run)

    with ThreadPoolExecutor(max_workers=2) as executor:
        results = list(
            executor.map(
                lambda _: ffmpeg_service.create_preview_proxy(
                    source_path,
                    duration_seconds=30,
                ),
                range(2),
            )
        )

    assert len(commands) == 1
    assert results[0][0] == results[1][0]
    assert sorted(result[1] for result in results) == [False, True]


def test_preview_proxy_routes_first_two_interleaved_channels() -> None:
    args = ffmpeg_service._preview_audio_output_args([8])

    filter_complex = _command_value(args, "-filter_complex")
    assert "[0:a:0]" in filter_complex
    assert "pan=stereo|c0=c0|c1=c1" in filter_complex


def test_media_probe_reuses_metadata_until_source_changes(
    tmp_path: Path,
    monkeypatch,
) -> None:
    source_path = tmp_path / "cached_probe.mxf"
    source_path.write_bytes(b"source")
    calls = 0

    def fake_run(
        command: list[str],
        timeout: int | None = None,
    ) -> subprocess.CompletedProcess[str]:
        nonlocal calls
        calls += 1
        payload = {
            "format": {"duration": "60.0", "format_name": "mxf"},
            "streams": [
                {
                    "codec_type": "video",
                    "codec_name": "mpeg2video",
                    "width": 1920,
                    "height": 1080,
                    "avg_frame_rate": "30/1",
                }
            ],
        }
        return subprocess.CompletedProcess(command, 0, json.dumps(payload), "")

    ffmpeg_service._probe_media_info_cached.cache_clear()
    monkeypatch.setattr(ffmpeg_service, "_run", fake_run)

    first = ffmpeg_service.probe_media_info(source_path)
    second = ffmpeg_service.probe_media_info(source_path)

    assert first == second
    assert calls == 1

    source_path.write_bytes(b"source changed")
    stat = source_path.stat()
    os.utime(
        source_path,
        ns=(stat.st_atime_ns, stat.st_mtime_ns + 1_000_000),
    )
    ffmpeg_service.probe_media_info(source_path)

    assert calls == 2


def test_audio_layout_probe_is_shared_by_count_and_channel_mapping(
    tmp_path: Path,
    monkeypatch,
) -> None:
    source_path = tmp_path / "broadcast_audio.mxf"
    source_path.write_bytes(b"source")
    calls = 0

    def fake_run(
        command: list[str],
        timeout: int | None = None,
    ) -> subprocess.CompletedProcess[str]:
        nonlocal calls
        calls += 1
        payload = {"streams": [{"channels": 1}, {"channels": 1}]}
        return subprocess.CompletedProcess(command, 0, json.dumps(payload), "")

    ffmpeg_service._audio_channel_counts_cached.cache_clear()
    monkeypatch.setattr(ffmpeg_service, "_run", fake_run)

    stream_count = ffmpeg_service._audio_stream_count(source_path)
    channel_counts = ffmpeg_service._audio_channel_counts(
        source_path,
        stream_count,
    )

    assert stream_count == 2
    assert channel_counts == [1, 1]
    assert calls == 1


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
