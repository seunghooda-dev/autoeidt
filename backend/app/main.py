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
def health() -> dict[str, str]:
    return {"status": "ok"}
