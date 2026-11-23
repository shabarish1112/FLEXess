from typing import Literal
from urllib.parse import urlsplit

from pydantic import Field, field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict
from sqlalchemy import create_engine
from sqlalchemy.engine import make_url


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file="../.env", extra="ignore", hide_input_in_errors=True)

    flex_environment: Literal["development", "staging", "production"] = "development"
    database_url: str | None = None
    database_ca_file: str | None = None
    database_pool_size: int = Field(default=5, ge=1, le=30)
    database_pool_overflow: int = Field(default=2, ge=0, le=20)
    identity_issuer: str | None = None
    identity_audience: str | None = None
    identity_jwks_url: str | None = None
    identity_client_id: str | None = None
    firebase_project_id: str | None = Field(default=None, pattern=r"^[a-z][a-z0-9-]{4,28}[a-z0-9]$")
    cors_origins: list[str] = Field(default_factory=list)

    @field_validator("cors_origins")
    @classmethod
    def validate_origins(cls, values):
        for value in values:
            parsed = urlsplit(value)
            if (parsed.scheme != "https" or not parsed.hostname or parsed.username is not None
                    or parsed.path or parsed.query or parsed.fragment):
                raise ValueError("CORS requires explicit HTTPS origins")
        return values

    @model_validator(mode="after")
    def validate_staging(self):
        if self.flex_environment in ("staging", "production"):
            if not self.database_url or make_url(self.database_url).drivername != "postgresql+psycopg":
                raise ValueError("Staging requires PostgreSQL over psycopg")
            if not self.database_ca_file:
                raise ValueError("Staging requires a trusted PostgreSQL CA file")
            if not self.firebase_project_id and not all((self.identity_issuer, self.identity_audience,
                                                        self.identity_client_id, self.identity_jwks_url)):
                raise ValueError("Staging requires a configured identity provider")
        return self


def make_engine(settings: Settings):
    if settings.database_url is None:
        return None
    url = make_url(settings.database_url)
    options = {"pool_pre_ping": True, "hide_parameters": True}
    if url.drivername == "postgresql+psycopg":
        # Transaction-pooling connections cannot depend on session-local prepared statements.
        options["connect_args"] = {"prepare_threshold": None, "connect_timeout": 5}
        options.update(pool_size=settings.database_pool_size,
                       max_overflow=settings.database_pool_overflow,
                       pool_timeout=5, pool_recycle=300)
        if settings.flex_environment in ("staging", "production"):
            # Put verified TLS at the connection boundary, overriding URL parameters.
            options["connect_args"].update({
                "sslmode": "verify-full", "sslrootcert": settings.database_ca_file,
                "connect_timeout": 5,
            })
    return create_engine(url, **options)
