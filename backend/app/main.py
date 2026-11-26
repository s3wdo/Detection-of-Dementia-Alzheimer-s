"""NeuroSense API."""
import logging
import time
from pathlib import Path
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from starlette.responses import JSONResponse
from starlette.staticfiles import StaticFiles
from starlette.types import ASGIApp, Message, Receive, Scope, Send

from app.core.config import get_settings
from app.core.errors import install_error_handlers
from app.ml.predictor import Predictor, build_predictor
from app.routers import admin, analyses, auth, patients, support

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
log = logging.getLogger("neurosense.api")


class BodySizeLimit:
    """Rejects request bodies over the limit before they are read into memory.
    Images arrive as base64 inside JSON, so the body is the only upload path."""

    def __init__(self, app: ASGIApp, max_bytes: int, larger: dict[str, int] | None = None):
        self.app, self.max_bytes = app, max_bytes
        # Paths allowed a bigger body (full MRI scans).
        self.larger = larger or {}

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            return await self.app(scope, receive, send)
        max_bytes = self.larger.get(scope.get("path", ""), self.max_bytes)

        too_large = JSONResponse(
            {"error": {"code": "PAYLOAD_TOO_LARGE", "message": "The request is too large."}}, status_code=413
        )
        declared = dict(scope["headers"]).get(b"content-length")
        if declared is not None and declared.isdigit() and int(declared) > max_bytes:
            return await too_large(scope, receive, send)

        received = 0
        response_started = False

        async def limited_receive() -> Message:
            nonlocal received
            message = await receive()
            if message["type"] == "http.request":
                received += len(message.get("body", b""))
                if received > max_bytes:
                    raise _BodyTooLarge
            return message

        async def tracking_send(message: Message) -> None:
            nonlocal response_started
            if message["type"] == "http.response.start":
                response_started = True
            await send(message)

        try:
            await self.app(scope, limited_receive, tracking_send)
        except _BodyTooLarge:
            if not response_started:
                await too_large(scope, receive, send)


class _BodyTooLarge(Exception):
    pass


def create_app(*, predictor: Predictor | None = None, start_worker: bool | None = None, brain_filter=None) -> FastAPI:
    settings = get_settings()

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        # The model is loaded once, here, and only from the server's own disk.
        app.state.predictor = predictor or build_predictor(settings)
        if brain_filter is not None:
            app.state.brain_filter = brain_filter
        else:
            from app.ml.brain_filter import build_brain_filter

            app.state.brain_filter = build_brain_filter(settings.brain_filter_path, settings.brain_filter_threshold)
        app.state.worker = None
        if settings.start_worker if start_worker is None else start_worker:
            from app.db.session import SessionLocal
            from app.services.analysis_worker import AnalysisWorker

            app.state.worker = AnalysisWorker(SessionLocal, app.state.predictor, settings, app.state.brain_filter)
            app.state.worker.start()
        yield
        if app.state.worker is not None:
            app.state.worker.stop()

    # The interactive API pages are for development; on the internet they stay off.
    public = settings.app_env == "production"
    app = FastAPI(
        title="NeuroSense API",
        version="0.1.0",
        lifespan=lifespan,
        docs_url=None if public else "/docs",
        redoc_url=None if public else "/redoc",
        openapi_url=None if public else "/openapi.json",
    )
    install_error_handlers(app)

    @app.middleware("http")
    async def request_log(request: Request, call_next):
        # Method, route template, status and duration only: no bodies, tokens,
        # names or results ever reach the log.
        started = time.perf_counter()
        response = await call_next(request)
        route = request.scope.get("route")
        log.info(
            "%s %s %s %.0fms",
            request.method,
            getattr(route, "path", "unmatched"),
            response.status_code,
            (time.perf_counter() - started) * 1000,
        )
        return response

    app.add_middleware(
        BodySizeLimit,
        max_bytes=settings.max_body_bytes,
        larger={"/api/v1/scans/volume": settings.max_volume_bytes},
    )

    @app.get("/health", tags=["health"])
    def health(request: Request) -> dict:
        active: Predictor = request.app.state.predictor
        return {
            "status": "ok",
            "model": "stub" if active.simulated else "loaded",
            "model_name": active.name,
            "model_version": active.version,
            # Full-scan (.nii) uploads need the brain detector.
            "full_scans": "enabled" if getattr(request.app.state, "brain_filter", None) is not None else "disabled",
        }

    for module in (auth, admin, patients, analyses, support):
        app.include_router(module.router, prefix="/api/v1")

    # The app's web build, when one has been copied to web/ (development only).
    web = Path("web")
    if (web / "index.html").is_file():
        app.mount("/", StaticFiles(directory=web, html=True), name="web")
    return app


app = create_app()
