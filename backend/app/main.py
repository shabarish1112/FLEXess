from contextlib import asynccontextmanager
import json
import logging
from uuid import uuid4

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError
from starlette.middleware.body_limit import RequestBodyLimitMiddleware

from .cloud import register_cloud
from .config import Settings, make_engine
from .identity import ConfiguredIdentityVerifier, FirebaseIdentityVerifier, IdentityVerifier, ManagedIdentityVerifier

logger = logging.getLogger("flex.api")


class Health(BaseModel):
    status: str


def create_app(settings: Settings | None = None, *, verifier: IdentityVerifier | None = None) -> FastAPI:
    settings = settings or Settings()
    engine = make_engine(settings)
    identity = (settings.identity_issuer, settings.identity_audience,
                settings.identity_jwks_url, settings.identity_client_id)
    if any(identity) and not all(identity):
        raise ValueError("Configure issuer, audience, JWKS, and client ID together")
    if verifier is None:
        providers = []
        if all(identity):
            providers.append(ManagedIdentityVerifier(*identity))
        if settings.firebase_project_id:
            providers.append(FirebaseIdentityVerifier(settings.firebase_project_id))
        if providers:
            verifier = ConfiguredIdentityVerifier(providers)

    @asynccontextmanager
    async def lifespan(_):
        try:
            yield
        finally:
            if engine is not None:
                engine.dispose()

    app = FastAPI(title="FLEX Foundation", lifespan=lifespan)
    app.add_middleware(RequestBodyLimitMiddleware, max_body_size=262144)

    @app.exception_handler(RequestValidationError)
    async def invalid_request(_: Request, __: RequestValidationError):
        return JSONResponse(status_code=422, content={"detail": "invalid_request"})

    @app.middleware("http")
    async def observe(request: Request, call_next):
        request_id = str(uuid4())
        try:
            response = await call_next(request)
        except Exception as exc:
            logger.error(json.dumps({"event": "unhandled_error", "request_id": request_id,
                                     "type": type(exc).__name__}))
            response = JSONResponse(status_code=500, content={"detail": "internal_error"})
        response.headers["X-Request-ID"] = request_id
        if request.scope.get("route") and request.scope["route"].path.startswith("/v1/"):
            response.headers["Cache-Control"] = "no-store"
        logger.info(json.dumps({"event": "request", "request_id": request_id,
                                "status": response.status_code}))
        return response

    if settings.cors_origins:
        app.add_middleware(CORSMiddleware, allow_origins=settings.cors_origins,
                           allow_methods=["GET", "POST"], allow_headers=["Authorization", "Content-Type"],
                           expose_headers=["X-Request-ID"])
    if engine is not None:
        register_cloud(app, engine, verifier)

    @app.get("/health/live", response_model=Health)
    def live():
        return Health(status="ok")

    @app.get("/health/ready", response_model=Health, responses={503: {"model": Health}})
    def ready():
        if engine is not None:
            try:
                with engine.connect() as connection:
                    connection.execute(text("SELECT 1"))
                return Health(status="ok")
            except SQLAlchemyError as exc:
                logger.warning(json.dumps({"event": "database_readiness_failed", "type": type(exc).__name__}))
        return JSONResponse(status_code=503, content={"status": "unavailable"})

    return app


app = create_app()
