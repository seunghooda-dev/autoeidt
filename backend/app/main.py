from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import get_settings
from app.routers.jobs import router as jobs_router
from app.routers.styles import router as styles_router
from app.routers.system import router as system_router
from app.storage import store


settings = get_settings()


@asynccontextmanager
async def lifespan(_app: FastAPI):
    if settings.task_runner == "inline":
        store.recover_interrupted_jobs()
    yield

app = FastAPI(title=settings.app_name, lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(jobs_router, prefix=settings.api_prefix)
app.include_router(styles_router, prefix=settings.api_prefix)
app.include_router(system_router, prefix=settings.api_prefix)


@app.get("/health")
def health() -> dict[str, object]:
    return {
        "status": "ok",
        "app": settings.app_name,
        "engine_version": "2026.07.11-v2-overlay-render-v1",
        "timeline_frame_rate": "30",
        "preview_proxy_seconds": settings.preview_proxy_seconds,
        "features": [
            "local_import",
            "local_probe",
            "local_preview_proxy",
            "preview_audio_mix_v1",
            "broadcast_audio_a1_a2_v2",
            "fast_proxy_preview_v2",
            "fast_proxy_preview_v3",
            "preview_reconnect_v1",
            "compatibility_preview_v1",
            "local_preview_file_v1",
            "safe_storage_cleanup_v1",
            "cancellable_jobs_v1",
            "recent_jobs_v1",
            "timeline_30p_ndf",
            "timeline_thumbnails_v1",
            "motion_keyframes_v1",
            "effect_aware_program_preview_v1",
            "windowed_program_preview_v1",
            "v2_overlay_render_v1",
        ],
    }
