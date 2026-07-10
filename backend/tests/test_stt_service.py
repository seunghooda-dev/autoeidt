from types import SimpleNamespace

import huggingface_hub

from app.services.stt_service import (
    _local_runtime_candidates,
    _resolved_local_model,
)


def test_explicit_local_whisper_model_is_preserved() -> None:
    assert _resolved_local_model("tiny") == "tiny"


def test_auto_model_prefers_complete_cached_quality_model(monkeypatch) -> None:
    cached_file = SimpleNamespace(file_name="model.bin", size_on_disk=1_000_000_000)
    cached_revision = SimpleNamespace(files=[cached_file])
    cached_repo = SimpleNamespace(
        repo_id="Systran/faster-whisper-medium",
        revisions=[cached_revision],
    )
    monkeypatch.setattr(
        huggingface_hub,
        "scan_cache_dir",
        lambda: SimpleNamespace(repos=[cached_repo]),
    )

    assert _resolved_local_model("auto") == "medium"


def test_explicit_cpu_runtime_uses_int8_for_auto_compute() -> None:
    assert _local_runtime_candidates("cpu", "auto") == [("cpu", "int8")]

