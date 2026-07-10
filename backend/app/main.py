from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import get_settings
from app.routers.jobs import router as jobs_router
from app.routers.styles import router as styles_router


settings = get_settings()

app = FastAPI(title=settings.app_name)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(jobs_router, prefix=settings.api_prefix)
app.include_router(styles_router, prefix=settings.api_prefix)


@app.get("/health")
def health() -> dict[str, object]:
    return {
        "status": "ok",
        "app": settings.app_name,
        "engine_version": "2026.07.10-fast-preview-v2",
        "timeline_frame_rate": "30",
        "preview_proxy_seconds": settings.preview_proxy_seconds,
        "features": [
            "local_import",
            "local_probe",
            "local_preview_proxy",
            "preview_audio_mix_v1",
            "broadcast_audio_a1_a2_v2",
            "fast_proxy_preview_v2",
            "timeline_30p_ndf",
        ],
    }
