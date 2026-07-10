from pathlib import Path

from app.services.ffmpeg_service import summarize_media_probe


def test_media_probe_summarizes_broadcast_mxf_op1a_like_file() -> None:
    summary = summarize_media_probe(
        Path("C:/media/news_source.mxf"),
        {
            "format": {
                "format_name": "mxf",
                "format_long_name": "MXF (Material eXchange Format)",
                "duration": "3600.000",
                "bit_rate": "50000000",
                "tags": {"timecode": "01:00:00;00"},
            },
            "streams": [
                {
                    "codec_type": "video",
                    "codec_name": "mpeg2video",
                    "codec_long_name": "MPEG-2 video",
                    "width": 1920,
                    "height": 1080,
                    "avg_frame_rate": "30000/1001",
                },
                {
                    "codec_type": "audio",
                    "codec_name": "pcm_s24le",
                    "channels": 1,
                    "channel_layout": "mono",
                },
                {
                    "codec_type": "audio",
                    "codec_name": "pcm_s24le",
                    "channels": 1,
                    "channel_layout": "mono",
                },
            ],
        },
    )

    assert summary["is_mxf"] is True
    assert summary["can_analyze"] is True
    assert summary["mxf_operational_pattern"] == "OP1a-like single-file MXF"
    assert summary["frame_rate"] == 29.97
    assert summary["source_frame_rate"] == 29.97
    assert summary["source_timecode"] == "01:00:00;00"
    assert summary["source_drop_frame"] is True
    assert summary["timeline_frame_rate"] == 30.0
    assert summary["timeline_timecode_mode"] == "non_drop"
    assert summary["timeline_timebase"] == "30p NDF"
    assert summary["timecode"] == "01:00:00:00"
    assert summary["audio_stream_count"] == 2
    assert summary["audio_channel_count"] == 2
    assert "A1 pcm_s24le mono" in summary["audio_summary"]
    assert any("drop-frame" in warning for warning in summary["warnings"])


def test_media_probe_warns_for_possible_op_atom_without_audio() -> None:
    summary = summarize_media_probe(
        Path("C:/media/camera_v01.mxf"),
        {
            "format": {
                "format_name": "mxf",
                "format_long_name": "MXF (Material eXchange Format)",
                "duration": "120.000",
            },
            "streams": [
                {
                    "codec_type": "video",
                    "codec_name": "dnxhd",
                    "width": 1920,
                    "height": 1080,
                    "avg_frame_rate": "25/1",
                }
            ],
        },
    )

    assert summary["can_analyze"] is True
    assert summary["audio_stream_count"] == 0
    assert summary["audio_channel_count"] == 0
    assert summary["mxf_operational_pattern"] == "Possible OP-Atom/separate essence MXF"
    assert any("OP-Atom" in warning for warning in summary["warnings"])
    assert any("30.00fps non-drop" in warning for warning in summary["warnings"])


def test_media_probe_clamps_invalid_source_timecode_to_30p_non_drop() -> None:
    summary = summarize_media_probe(
        Path("C:/media/news_source.mxf"),
        {
            "format": {
                "format_name": "mxf",
                "duration": "60.000",
                "tags": {"timecode": "01:61:99;35"},
            },
            "streams": [
                {
                    "codec_type": "video",
                    "codec_name": "mpeg2video",
                    "width": 1920,
                    "height": 1080,
                    "avg_frame_rate": "30/1",
                }
            ],
        },
    )

    assert summary["timecode"] == "01:59:59:29"
    assert summary["timeline_frame_rate"] == 30.0
    assert summary["timeline_timecode_mode"] == "non_drop"


def test_media_probe_counts_interleaved_broadcast_audio_channels() -> None:
    summary = summarize_media_probe(
        Path("C:/media/interleaved_8ch.mxf"),
        {
            "format": {"format_name": "mxf", "duration": "20.000"},
            "streams": [
                {
                    "codec_type": "video",
                    "codec_name": "mpeg2video",
                    "width": 1920,
                    "height": 1080,
                    "avg_frame_rate": "30000/1001",
                },
                {
                    "codec_type": "audio",
                    "codec_name": "pcm_s24le",
                    "channels": 8,
                    "channel_layout": "7.1",
                },
            ],
        },
    )

    assert summary["audio_stream_count"] == 1
    assert summary["audio_channel_count"] == 8
    assert "8ch" in summary["audio_summary"] or "7.1" in summary["audio_summary"]
    assert any("다중 오디오 채널" in warning for warning in summary["warnings"])
