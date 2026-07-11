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


def test_render_composites_v2_overlay_before_captions(
    tmp_path: Path,
    monkeypatch,
) -> None:
    commands: list[list[str]] = []
    overlay_path = tmp_path / "broll.mov"
    overlay_path.write_bytes(b"overlay")

    def fake_run(
        command: list[str],
        timeout: int | None = None,
    ) -> subprocess.CompletedProcess[str]:
        commands.append(command)
        return subprocess.CompletedProcess(command, 0, "", "")

    monkeypatch.setattr(ffmpeg_service, "get_settings", lambda: _FakeSettings(tmp_path))
    monkeypatch.setattr(ffmpeg_service, "_audio_stream_count", lambda path: 1)
    monkeypatch.setattr(ffmpeg_service, "_run", fake_run)

    ffmpeg_service.render_highlights_reencoded(
        Path("C:/media/source.mxf"),
        [{"order": 1, "start": 0, "end": 12, "reason": "base"}],
        tmp_path / "overlay-output.mp4",
        video_overlays=[
            {
                "id": "v2-1",
                "source_path": str(overlay_path),
                "source_name": "broll.mov",
                "timeline_start": 2,
                "timeline_end": 8,
                "source_start": 1,
                "source_end": 7,
                "opacity": 0.8,
                "scale": 0.4,
                "position_x": 0.5,
                "position_y": -0.4,
                "muted": False,
                "audio_volume": 0.5,
                "audio_pan": 0.25,
                "audio_fade_in": 0.5,
                "audio_fade_out": 0.75,
            }
        ],
    )

    command = commands[-1]
    filter_complex = _command_value(command, "-filter_complex")
    input_paths = [
        command[index + 1]
        for index, argument in enumerate(command[:-1])
        if argument == "-i"
    ]
    assert str(overlay_path.resolve()) in input_paths
    assert "[1:v:0]trim=start=1.000000:end=7.000000" in filter_complex
    assert "scale=768:432:force_original_aspect_ratio=decrease" in filter_complex
    assert "colorchannelmixer=aa=0.800000" in filter_complex
    assert "setpts=PTS+2.000000/TB" in filter_complex
    assert "enable='between(t,2.000000,8.000000)'" in filter_complex
    assert "[v2base0]fps=30,format=yuv420p[outv]" in filter_complex
    assert "[1:a:0]atrim=start=1.000000:end=7.000000" in filter_complex
    assert "volume=0.500" in filter_complex
    assert "pan=stereo|c0=0.750000*c0|c1=1.000000*c1" in filter_complex
    assert "afade=t=in:st=0:d=0.500000" in filter_complex
    assert "afade=t=out:st=5.250000:d=0.750000" in filter_complex
    assert "adelay=delays=2000:all=1" in filter_complex
    assert "amix=inputs=2:duration=longest:normalize=0" in filter_complex
    assert ";[a3mix0]anull[outa]" in filter_complex


def test_render_places_broadcast_graphics_before_captions(
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
    monkeypatch.setattr(ffmpeg_service, "_run", fake_run)

    output_path = tmp_path / "graphics-output.mp4"
    ffmpeg_service.render_highlights_reencoded(
        Path("C:/media/source.mxf"),
        [{"order": 1, "start": 0, "end": 8, "reason": "base"}],
        output_path,
        graphics=[
            {
                "id": "g1-election",
                "timeline_start": 1,
                "timeline_end": 6,
                "preset": "lower_third",
                "headline": "Election update",
                "subheadline": "Live from Seoul",
                "position_x": 0.1,
                "position_y": 0.8,
                "opacity": 0.75,
                "accent_color": "#EF4444",
            }
        ],
        captions=[
            {"order": 1, "start": 2, "end": 3, "text": "caption", "enabled": True}
        ],
    )

    graphic_file = output_path.with_suffix(".graphics.ass")
    contents = graphic_file.read_text(encoding="utf-8")
    filter_complex = _command_value(commands[-1], "-filter_complex")
    assert "Dialogue: 1,0:00:01.00,0:00:06.00,Graphic" in contents
    assert r"\pos(192,864)" in contents
    assert r"\alpha&H40&" in contents
    assert r"\1c&H004444EF&" in contents
    assert "Election update" in contents
    assert "Live from Seoul" in contents
    assert filter_complex.index(".graphics.ass") < filter_complex.index(".srt")


def test_render_mixes_standalone_audio_clip_on_auxiliary_track(
    tmp_path: Path,
    monkeypatch,
) -> None:
    commands: list[list[str]] = []
    audio_path = tmp_path / "music.wav"
    audio_path.write_bytes(b"audio")

    def fake_run(
        command: list[str],
        timeout: int | None = None,
    ) -> subprocess.CompletedProcess[str]:
        commands.append(command)
        return subprocess.CompletedProcess(command, 0, "", "")

    monkeypatch.setattr(ffmpeg_service, "get_settings", lambda: _FakeSettings(tmp_path))
    monkeypatch.setattr(ffmpeg_service, "_audio_stream_count", lambda path: 1)
    monkeypatch.setattr(ffmpeg_service, "_run", fake_run)

    ffmpeg_service.render_highlights_reencoded(
        Path("C:/media/source.mxf"),
        [{"order": 1, "start": 0, "end": 12, "reason": "base"}],
        tmp_path / "audio-output.mp4",
        audio_clips=[
            {
                "id": "music-1",
                "source_path": str(audio_path),
                "source_name": "music.wav",
                "timeline_start": 2.5,
                "timeline_end": 8,
                "source_start": 1,
                "source_end": 6.5,
                "track": 8,
                "volume": 0.6,
                "pan": -0.4,
                "fade_in": 0.5,
                "fade_out": 0.75,
            },
            {
                "id": "disabled-offline",
                "source_path": str(tmp_path / "missing.wav"),
                "timeline_start": 0,
                "timeline_end": 1,
                "source_start": 0,
                "source_end": 1,
                "enabled": False,
            },
        ],
    )

    command = commands[-1]
    filter_complex = _command_value(command, "-filter_complex")
    input_paths = [
        command[index + 1]
        for index, argument in enumerate(command[:-1])
        if argument == "-i"
    ]
    assert input_paths[1:] == [str(audio_path.resolve())]
    assert "[1:a:0]atrim=start=1.000000:end=6.500000" in filter_complex
    assert "aformat=sample_rates=48000:channel_layouts=stereo" in filter_complex
    assert "volume=0.600" in filter_complex
    assert "pan=stereo|c0=1.000000*c0|c1=0.600000*c1" in filter_complex
    assert "afade=t=in:st=0:d=0.500000" in filter_complex
    assert "afade=t=out:st=4.750000:d=0.750000" in filter_complex
    assert "adelay=delays=2500:all=1" in filter_complex
    assert "[standaloneaudio0]" in filter_complex
    assert ";[standalonemix0]anull[outa]" in filter_complex


def test_render_layers_higher_video_tracks_last(
    tmp_path: Path,
    monkeypatch,
) -> None:
    commands: list[list[str]] = []
    v2_path = tmp_path / "v2.mov"
    v4_path = tmp_path / "v4.mov"
    v2_path.write_bytes(b"v2")
    v4_path.write_bytes(b"v4")

    def fake_run(
        command: list[str],
        timeout: int | None = None,
    ) -> subprocess.CompletedProcess[str]:
        commands.append(command)
        return subprocess.CompletedProcess(command, 0, "", "")

    monkeypatch.setattr(ffmpeg_service, "get_settings", lambda: _FakeSettings(tmp_path))
    monkeypatch.setattr(ffmpeg_service, "_audio_stream_count", lambda path: 1)
    monkeypatch.setattr(ffmpeg_service, "_run", fake_run)

    ffmpeg_service.render_highlights_reencoded(
        Path("C:/media/source.mxf"),
        [{"order": 1, "start": 0, "end": 6, "reason": "base"}],
        tmp_path / "layered.mp4",
        video_overlays=[
            {
                "id": "top",
                "source_path": str(v4_path),
                "timeline_start": 0,
                "timeline_end": 2,
                "source_start": 0,
                "source_end": 2,
                "video_track": 4,
            },
            {
                "id": "lower",
                "source_path": str(v2_path),
                "timeline_start": 0,
                "timeline_end": 2,
                "source_start": 0,
                "source_end": 2,
                "video_track": 2,
            },
        ],
    )

    command = commands[-1]
    filter_complex = _command_value(command, "-filter_complex")
    input_paths = [
        command[index + 1]
        for index, argument in enumerate(command[:-1])
        if argument == "-i"
    ]
    assert input_paths[1:] == [str(v2_path.resolve()), str(v4_path.resolve())]
    assert filter_complex.index("[1:v:0]") < filter_complex.index("[2:v:0]")
    assert filter_complex.index("[v2base0]") < filter_complex.index("[v2base1]")


def test_render_builds_video_and_constant_power_audio_transitions(
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
            {"order": 1, "start": 0, "end": 4, "reason": "opener"},
            {
                "order": 2,
                "start": 10,
                "end": 14,
                "reason": "answer",
                "transition_type": "cross_dissolve",
                "transition_duration": 0.5,
            },
            {
                "order": 3,
                "start": 20,
                "end": 24,
                "reason": "close",
                "transition_type": "dip_black",
                "transition_duration": 0.2,
            },
        ],
        tmp_path / "transitions.mp4",
    )

    filter_complex = _command_value(commands[-1], "-filter_complex")
    assert "xfade=transition=fade:duration=0.500000:offset=3.500000" in filter_complex
    assert "acrossfade=d=0.500000:c1=qsin:c2=qsin" in filter_complex
    assert "xfade=transition=fadeblack:duration=0.200000:offset=7.300000" in filter_complex
    assert "acrossfade=d=0.200000:c1=qsin:c2=qsin" in filter_complex
    assert ffmpeg_service.sequence_output_duration_seconds(
        [
            {"start": 0, "end": 4},
            {
                "start": 10,
                "end": 14,
                "transition_type": "cross_dissolve",
                "transition_duration": 0.5,
            },
            {
                "start": 20,
                "end": 24,
                "transition_type": "dip_black",
                "transition_duration": 0.2,
            },
        ]
    ) == 11.3


def test_render_applies_motion_rotation_and_true_opacity(
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
    monkeypatch.setattr(ffmpeg_service, "_source_video_dimensions", lambda path: (1920, 1080))
    monkeypatch.setattr(ffmpeg_service, "_run", fake_run)

    ffmpeg_service.render_highlights_reencoded(
        Path("C:/media/source.mxf"),
        [
            {
                "order": 1,
                "start": 0,
                "end": 2,
                "reason": "motion",
                "video_opacity": 0.7,
                "video_scale": 1.25,
                "video_position_x": 0.2,
                "video_position_y": -0.3,
                "video_rotation": 15,
            }
        ],
        tmp_path / "motion.mp4",
    )

    filter_complex = _command_value(commands[-1], "-filter_complex")
    assert "scale=2400:1350,format=rgba" in filter_complex
    assert "rotate=0.261799388:ow=iw:oh=ih:c=black@0" in filter_complex
    assert "colorchannelmixer=aa=0.700000" in filter_complex
    assert "color=c=black:s=1920x1080:d=2.000000:r=30" in filter_complex
    assert "(1920-w)/2+(0.200000)*1920/2" in filter_complex
    assert "(1080-h)/2+(-0.300000)*1080/2" in filter_complex
    assert "shortest=1:format=auto" in filter_complex


def test_render_interpolates_motion_keyframes_on_output_time(
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
    monkeypatch.setattr(ffmpeg_service, "_source_video_dimensions", lambda path: (1920, 1080))
    monkeypatch.setattr(ffmpeg_service, "_run", fake_run)

    ffmpeg_service.render_highlights_reencoded(
        Path("C:/media/source.mxf"),
        [
            {
                "order": 1,
                "start": 0,
                "end": 4,
                "reason": "animated motion",
                "motion_keyframes": [
                    {
                        "time": 0,
                        "opacity": 1,
                        "scale": 1,
                        "position_x": 0,
                        "position_y": 0,
                        "rotation": 0,
                    },
                    {
                        "time": 4,
                        "opacity": 0.5,
                        "scale": 1.5,
                        "position_x": 0.25,
                        "position_y": -0.2,
                        "rotation": 12,
                    },
                ],
            }
        ],
        tmp_path / "animated-motion.mp4",
    )

    filter_complex = _command_value(commands[-1], "-filter_complex")
    assert "pad=w=iw*2:h=ih*2:x=iw/2:y=ih/2:color=black@0" in filter_complex
    assert "zoompan=z='2*(" in filter_complex
    assert "clip((ot-0.000000)/4.000000,0,1)" in filter_complex
    assert "d=1:s=1920x1080:fps=30" in filter_complex
    assert "rotate='(" in filter_complex
    assert "clip((t-0.000000)/4.000000,0,1)" in filter_complex
    assert "geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)'" in filter_complex
    assert "clip((T-0.000000)/4.000000,0,1)" in filter_complex
    assert "[motioncanvas0][motion0]overlay=x='0':y='0'" in filter_complex


def test_render_interpolates_volume_for_main_overlay_and_aux_audio(
    tmp_path: Path,
    monkeypatch,
) -> None:
    commands: list[list[str]] = []
    overlay_path = tmp_path / "overlay.mov"
    audio_path = tmp_path / "music.wav"
    overlay_path.write_bytes(b"overlay")
    audio_path.write_bytes(b"audio")

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
                "end": 4,
                "reason": "main volume ride",
                "audio_volume": 0,
                "audio_gain_keyframes": [
                    {"time": 0, "volume": 0},
                    {"time": 4, "volume": 1},
                ],
            }
        ],
        tmp_path / "audio-automation.mp4",
        video_overlays=[
            {
                "id": "overlay-audio",
                "source_path": str(overlay_path),
                "timeline_start": 0,
                "timeline_end": 4,
                "source_start": 0,
                "source_end": 4,
                "muted": False,
                "audio_volume": 0,
                "audio_gain_keyframes": [
                    {"time": 0, "volume": 0.25},
                    {"time": 4, "volume": 1.25},
                ],
            }
        ],
        audio_clips=[
            {
                "id": "music",
                "source_path": str(audio_path),
                "timeline_start": 0,
                "timeline_end": 4,
                "source_start": 0,
                "source_end": 4,
                "volume": 0,
                "gain_keyframes": [
                    {"time": 0, "volume": 0.5},
                    {"time": 4, "volume": 1.5},
                ],
            }
        ],
    )

    command = commands[-1]
    filter_complex = _command_value(command, "-filter_complex")
    input_paths = [
        command[index + 1]
        for index, argument in enumerate(command[:-1])
        if argument == "-i"
    ]
    assert input_paths[1:] == [str(overlay_path.resolve()), str(audio_path.resolve())]
    assert filter_complex.count(":eval=frame") == 3
    assert "volume='if(lt(t,4.000000)" in filter_complex
    assert "0.000000+(1.000000)*clip((t-0.000000)/4.000000,0,1)" in filter_complex
    assert "0.250000+(1.000000)*clip((t-0.000000)/4.000000,0,1)" in filter_complex
    assert "0.500000+(1.000000)*clip((t-0.000000)/4.000000,0,1)" in filter_complex


def test_program_preview_proxy_uses_effect_segment_and_fast_preview_size(
    tmp_path: Path,
    monkeypatch,
) -> None:
    source = tmp_path / "source.mxf"
    source.write_bytes(b"broadcast-source")
    overlay_source = tmp_path / "broll.mov"
    overlay_source.write_bytes(b"overlay-source")
    audio_source = tmp_path / "music.wav"
    audio_source.write_bytes(b"audio-source")
    calls: list[dict] = []

    def fake_render(
        video_path: Path,
        segments: list[dict],
        output_path: Path,
        video_args: list[str],
        **kwargs,
    ) -> Path:
        calls.append(
            {
                "video_path": video_path,
                "segments": segments,
                "video_args": video_args,
                "output_size": kwargs.get("output_size"),
                "processing_size": kwargs.get("processing_size"),
                "video_overlays": kwargs.get("video_overlays"),
                "audio_clips": kwargs.get("audio_clips"),
                "graphics": kwargs.get("graphics"),
            }
        )
        output_path.write_bytes(b"preview")
        return output_path

    monkeypatch.setattr(ffmpeg_service, "get_settings", lambda: _FakeSettings(tmp_path))
    monkeypatch.setattr(
        ffmpeg_service,
        "_render_reencode_with_video_args",
        fake_render,
    )
    segment = {
        "order": 7,
        "start": 10,
        "end": 14,
        "playback_speed": 2,
        "reason": "animated preview",
        "motion_keyframes": [
            {"time": 0, "scale": 1},
            {"time": 2, "scale": 2},
        ],
    }

    overlays = [
        {
            "id": "v2-preview",
            "source_path": str(overlay_source),
            "source_name": "broll.mov",
            "timeline_start": 1,
            "timeline_end": 2,
            "source_start": 0,
            "source_end": 1,
        }
    ]
    audio_clips = [
        {
            "id": "audio-preview",
            "source_path": str(audio_source),
            "source_name": "music.wav",
            "timeline_start": 0.5,
            "timeline_end": 1.5,
            "source_start": 2,
            "source_end": 3,
            "track": 8,
        }
    ]
    graphics = [
        {
            "id": "g1-preview",
            "timeline_start": 0.5,
            "timeline_end": 1.5,
            "preset": "headline",
            "headline": "Preview headline",
        }
    ]
    output, cached, source_start, duration = ffmpeg_service.create_program_preview_proxy(
        source,
        segment,
        video_overlays=overlays,
        audio_clips=audio_clips,
        graphics=graphics,
    )
    cached_output, cached_again, _, _ = (
        ffmpeg_service.create_program_preview_proxy(
            source,
            segment,
            video_overlays=overlays,
            audio_clips=audio_clips,
            graphics=graphics,
        )
    )

    assert output == cached_output
    assert cached is False
    assert cached_again is True
    assert source_start == 10
    assert duration == 2
    assert calls[0]["segments"][0]["order"] == 1
    assert calls[0]["segments"][0]["motion_keyframes"][1]["scale"] == 2
    assert calls[0]["video_args"] == [
        "-c:v",
        "libx264",
        "-preset",
        "ultrafast",
        "-crf",
        "28",
    ]
    assert calls[0]["output_size"] == (960, 540)
    assert calls[0]["processing_size"] == (960, 540)
    assert calls[0]["video_overlays"][0]["id"] == "v2-preview"
    assert calls[0]["video_overlays"][0]["source_path"] == str(
        overlay_source.resolve()
    )
    assert calls[0]["audio_clips"][0]["id"] == "audio-preview"
    assert calls[0]["audio_clips"][0]["source_path"] == str(
        audio_source.resolve()
    )
    assert calls[0]["graphics"][0]["headline"] == "Preview headline"

    overlay_source.write_bytes(b"updated-overlay-source")
    changed_output, changed_cached, _, _ = (
        ffmpeg_service.create_program_preview_proxy(
            source,
            segment,
            video_overlays=overlays,
            audio_clips=audio_clips,
            graphics=graphics,
        )
    )
    assert changed_output != output
    assert changed_cached is False
    assert len(calls) == 2

    audio_source.write_bytes(b"updated-audio-source")
    audio_changed_output, audio_changed_cached, _, _ = (
        ffmpeg_service.create_program_preview_proxy(
            source,
            segment,
            video_overlays=overlays,
            audio_clips=audio_clips,
            graphics=graphics,
        )
    )
    assert audio_changed_output != changed_output
    assert audio_changed_cached is False
    assert len(calls) == 3

    graphics[0]["headline"] = "Updated preview headline"
    graphic_changed_output, graphic_changed_cached, _, _ = (
        ffmpeg_service.create_program_preview_proxy(
            source,
            segment,
            video_overlays=overlays,
            audio_clips=audio_clips,
            graphics=graphics,
        )
    )
    assert graphic_changed_output != audio_changed_output
    assert graphic_changed_cached is False
    assert len(calls) == 4


def test_program_preview_window_remaps_effects_audio_and_fades(
    tmp_path: Path,
    monkeypatch,
) -> None:
    source = tmp_path / "window-source.mxf"
    source.write_bytes(b"broadcast-window-source")
    rendered_segments: list[dict] = []

    def fake_render(
        video_path: Path,
        segments: list[dict],
        output_path: Path,
        video_args: list[str],
        **kwargs,
    ) -> Path:
        rendered_segments.extend(segments)
        output_path.write_bytes(b"window-preview")
        return output_path

    monkeypatch.setattr(ffmpeg_service, "get_settings", lambda: _FakeSettings(tmp_path))
    monkeypatch.setattr(
        ffmpeg_service,
        "_render_reencode_with_video_args",
        fake_render,
    )
    segment = {
        "order": 4,
        "start": 10,
        "end": 30,
        "audio_start": 100,
        "audio_end": 120,
        "playback_speed": 2,
        "reason": "long animated clip",
        "video_fade_in": 1,
        "video_fade_out": 1,
        "audio_fade_in": 1,
        "audio_fade_out": 1,
        "audio_gain_keyframes": [
            {"time": 0, "volume": 0.2},
            {"time": 10, "volume": 1.2},
        ],
        "motion_keyframes": [
            {"time": 0, "scale": 1},
            {"time": 10, "scale": 3},
        ],
        "focus_keyframes": [
            {"time": 0, "x": 0.2, "y": 0.3},
            {"time": 20, "x": 0.8, "y": 0.7},
        ],
    }

    _, _, source_start, duration = ffmpeg_service.create_program_preview_proxy(
        source,
        segment,
        source_start_seconds=18,
        duration_seconds=3,
    )

    window = rendered_segments[0]
    assert source_start == 18
    assert duration == 3
    assert window["start"] == 18
    assert window["end"] == 24
    assert window["audio_start"] == 108
    assert window["audio_end"] == 114
    assert window["video_fade_in"] == 0
    assert window["video_fade_out"] == 0
    assert window["audio_fade_in"] == 0
    assert window["audio_fade_out"] == 0
    assert window["motion_keyframes"][0]["time"] == 0
    assert window["motion_keyframes"][0]["scale"] == 1.8
    assert window["motion_keyframes"][-1]["time"] == 3
    assert window["motion_keyframes"][-1]["scale"] == 2.4
    assert window["audio_gain_keyframes"][0]["time"] == 0
    assert abs(window["audio_gain_keyframes"][0]["volume"] - 0.6) < 0.000001
    assert window["audio_gain_keyframes"][-1]["time"] == 3
    assert abs(window["audio_gain_keyframes"][-1]["volume"] - 0.9) < 0.000001
    assert window["focus_keyframes"][0]["time"] == 0
    assert abs(window["focus_keyframes"][0]["x"] - 0.44) < 0.000001
    assert window["focus_keyframes"][-1]["time"] == 6
    assert abs(window["focus_keyframes"][-1]["x"] - 0.62) < 0.000001


def test_caption_timing_uses_transition_adjusted_sequence_positions(
    tmp_path: Path,
) -> None:
    output = ffmpeg_service._write_caption_srt(
        [
            {"start": 0, "end": 1, "text": "first", "enabled": True},
            {"start": 10, "end": 11, "text": "second", "enabled": True},
        ],
        [
            {"order": 1, "start": 0, "end": 4, "reason": "opener"},
            {
                "order": 2,
                "start": 10,
                "end": 14,
                "reason": "answer",
                "transition_type": "cross_dissolve",
                "transition_duration": 0.5,
            },
        ],
        tmp_path / "captions.srt",
    )

    assert output is not None
    contents = output.read_text(encoding="utf-8")
    assert "00:00:00,000 --> 00:00:01,000" in contents
    assert "00:00:03,500 --> 00:00:04,500" in contents


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


def test_timeline_thumbnail_is_frame_snapped_deinterlaced_and_cached(
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
        Path(command[-1]).write_bytes(b"jpeg")
        return subprocess.CompletedProcess(command, 0, "", "")

    monkeypatch.setattr(ffmpeg_service, "get_settings", lambda: _FakeSettings(tmp_path))
    monkeypatch.setattr(ffmpeg_service, "_run", fake_run)

    first = ffmpeg_service.create_timeline_thumbnail(
        source_path,
        time_seconds=5.119,
        width=320,
    )
    second = ffmpeg_service.create_timeline_thumbnail(
        source_path,
        time_seconds=5.119,
        width=320,
    )

    assert len(commands) == 1
    command = commands[0]
    assert first[0].name.startswith("thumb_")
    assert first[0].suffix == ".jpg"
    assert first[1] is False
    assert abs(first[2] - (154 / 30)) < 1e-9
    assert first[3] == 320
    assert second[0] == first[0]
    assert second[1] is True
    assert _command_value(command, "-ss") == "5.133"
    assert _command_value(command, "-frames:v") == "1"
    assert "yadif=deint=interlaced" in _command_value(command, "-vf")
    assert "scale=320:-2" in _command_value(command, "-vf")


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
