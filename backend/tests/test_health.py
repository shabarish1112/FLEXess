from fastapi.testclient import TestClient
from app.config import Settings
from app.main import create_app

def test_health_without_database():
    client = TestClient(create_app(Settings(database_url=None)))
    assert client.get("/health/live").json() == {"status": "ok"}
    assert client.get("/health/ready").status_code == 503
    assert client.get("/diary-entries").status_code == 404

def test_ready_with_database(tmp_path):
    client = TestClient(create_app(Settings(database_url=f"sqlite:///{tmp_path / 'db.sqlite'}")))
    assert client.get("/health/ready").json() == {"status": "ok"}

def test_staging_requires_trusted_database_configuration():
    import pytest
    from pydantic import ValidationError
    from app.config import make_engine

    values = dict(flex_environment="staging",
                  database_url="postgresql+psycopg://flex@localhost/flex?sslmode=disable",
                  identity_issuer="https://issuer.example.invalid/",
                  identity_audience="urn:flex:staging",
                  identity_client_id="native-test",
                  identity_jwks_url="https://issuer.example.invalid/jwks")
    with pytest.raises(ValidationError, match="trusted PostgreSQL CA"):
        Settings(**values)
    with pytest.raises(ValidationError, match="explicit HTTPS origins"):
        Settings(**values, database_ca_file="/test/ca.pem", cors_origins=["*"])
    engine = make_engine(Settings(**values, database_ca_file="/test/ca.pem"))
    from sqlalchemy import event
    observed = {}
    def capture(_dialect, _record, _args, params):
        observed.update(params)
        raise RuntimeError("isolated test")
    event.listen(engine, "do_connect", capture)
    with pytest.raises(RuntimeError, match="isolated test"):
        engine.connect()
    engine.dispose()
    assert observed["sslmode"] == "verify-full"
    assert observed["sslrootcert"] == "/test/ca.pem"
    assert observed["prepare_threshold"] is None


def test_production_enforces_database_and_identity_configuration():
    import pytest
    from pydantic import ValidationError
    with pytest.raises(ValidationError):
        Settings(flex_environment="production", database_url="sqlite://")
    settings = Settings(flex_environment="production", database_url="postgresql+psycopg://flex@localhost/flex",
                        database_ca_file="/test/ca.pem", firebase_project_id="flex-fitness-98e76")
    assert settings.firebase_project_id == "flex-fitness-98e76"


def test_oversized_and_chunked_requests_are_rejected():
    client = TestClient(create_app(Settings(database_url="sqlite://")))
    assert client.post('/v1/account/link', content=b'x' * 262145).status_code == 413
    assert client.post('/v1/account/link', content=iter([b'x' * 150000, b'x' * 150000])).status_code == 413
