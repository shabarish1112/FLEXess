import os
import time
from types import SimpleNamespace
from uuid import uuid4

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, update

from app.config import Settings
from app.identity import ManagedIdentityVerifier
from app.main import create_app
from app.models import Base, SyncReceipt, User

ISSUER = "https://identity.example.invalid/"
AUDIENCE = "urn:flex:test"
CLIENT = "flex-native-test"


@pytest.fixture(scope="module")
def key():
    return rsa.generate_private_key(public_exponent=65537, key_size=2048)


@pytest.fixture
def api(tmp_path, key):
    postgres = os.environ.get("FLEX_TEST_POSTGRES_URL")
    url = postgres or f"sqlite:///{tmp_path / 'isolated.db'}"
    engine = create_engine(url)
    if not postgres:
        Base.metadata.create_all(engine)
    verifier = ManagedIdentityVerifier(ISSUER, AUDIENCE, f"{ISSUER}.well-known/jwks.json", CLIENT)
    # The JWT verifier still checks the real signature and claims. Only JWKS transport is isolated.
    verifier.keys = SimpleNamespace(get_signing_key_from_jwt=lambda _: SimpleNamespace(key=key.public_key()))
    with TestClient(create_app(Settings(database_url=url), verifier=verifier)) as client:
        yield client, engine
    engine.dispose()


def token(key, subject, *, expires=None, **claims):
    now = int(time.time())
    return jwt.encode({"iss": ISSUER, "aud": AUDIENCE, "sub": subject, "iat": now,
                       "exp": now + 120 if expires is None else expires, "jti": str(uuid4()),
                       "client_id": CLIENT, **claims},
                      key, algorithm="RS256", headers={"typ": "at+jwt", "kid": "test"})


def bearer(key, subject, **claims):
    return {"Authorization": f"Bearer {token(key, subject, **claims)}"}


def draft(record=None, action="create", revision=0, **fields):
    return {"operation_id": str(uuid4()), "record_id": record or str(uuid4()), "kind": "weight",
            "action": action, "base_revision": revision, "payload_version": 1,
            "payload": None if action == "delete" else {"day": "2026-11-17", "grams": 70000}, **fields}


def test_token_validation_and_disabled_account(api, key):
    client, engine = api
    subject = str(uuid4())
    assert client.get("/v1/me").status_code == 401
    for headers in (
        {"Authorization": "Bearer invalid"},
        bearer(key, subject, expires=1), bearer(key, subject, aud="other"),
        bearer(key, subject, iss="https://other.example.invalid"),
        bearer(key, subject, client_id="other"),
        bearer(rsa.generate_private_key(public_exponent=65537, key_size=2048), subject),
    ):
        assert client.get("/v1/me", headers=headers).status_code == 401
    headers = bearer(key, subject)
    first = client.get("/v1/me", headers=headers)
    assert first.status_code == 200
    assert client.get("/v1/me", headers=headers).json() == first.json()
    with engine.begin() as db:
        db.execute(update(User).where(User.id == first.json()["id"]).values(active=False))
    assert client.get("/v1/me", headers=headers).status_code == 403


def test_owner_scope_and_read_success(api, key):
    client, _ = api
    alice, bob = (bearer(key, str(uuid4())) for _ in range(2))
    op = draft()
    rid = op["record_id"]
    submit = "/v1/sync/operations"
    assert client.post(submit, json=op).status_code == 401
    assert client.post(submit, json=op, headers=alice).status_code == 200
    route = f"/v1/records/weight/{rid}"
    assert client.get(route, headers=alice).json()["payload"]["grams"] == 70000
    assert client.get(route, headers=bob).status_code == 404
    assert client.get("/v1/records/weight", headers=bob).json() == []
    assert client.get("/v1/sync/changes", headers=bob).json() == []
    for action in ("update", "delete"):
        assert client.post(submit, json=draft(rid, action, 1), headers=bob).status_code == 404
    for body in (
        {**draft(), "owner_id": str(uuid4())},
        draft(payload={"day": "2026-11-17", "grams": -1}),
        draft(payload_version=2),
    ):
        assert client.post(submit, json=body, headers=alice).status_code == 422


def test_replay_tombstone_and_stale_revisions(api, key):
    client, engine = api
    headers = bearer(key, str(uuid4()))
    submit = "/v1/sync/operations"
    create = draft()
    rid = create["record_id"]
    def send(body):
        return client.post(submit, json=body, headers=headers)
    assert send(draft(rid, "update", 1)).status_code == 404
    first = send(create)
    assert first.status_code == 200
    assert first.json() == send(create).json()
    assert send({**create, "payload": {"day": "2026-11-17", "grams": 72000}}).status_code == 409
    edit = draft(rid, "update", 1, payload={"day": "2026-11-17", "grams": 71000})
    second = send(edit)
    assert second.status_code == 200 and second.json()["record"]["revision"] == 2
    assert second.json() == send(edit).json()
    conflict = send(draft(rid, "update", 1))
    assert conflict.status_code == 409 and conflict.json()["detail"]["current"]["revision"] == 2
    remove = draft(rid, "delete", 2)
    third = send(remove)
    assert third.status_code == 200 and third.json()["record"]["deleted"]
    assert third.json() == send(remove).json()
    assert send(draft(rid, "update", 3)).status_code == 409
    assert client.get(f"/v1/records/weight/{rid}", headers=headers).status_code == 404
    changes = client.get("/v1/sync/changes", params={"after": 1}, headers=headers)
    assert changes.json() == [second.json(), third.json()]
    with engine.connect() as db:
        assert db.execute(SyncReceipt.__table__.select().where(
            SyncReceipt.operation_id == create["operation_id"])).one().result == first.json()


@pytest.mark.parametrize(("kind", "payload"), [
    ("profile", {"display_name": "Test"}),
    ("goals", {"day": "2026-11-17", "calories": 2000, "protein_mg": 120000}),
    ("diary", {"day": "2026-11-17", "meal": "breakfast", "name": "Test food", "serving": "100 g",
               "quantity_milli": 1000, "nutrients": {"energy": 97000, "fiber": None}}),
    ("water", {"day": "2026-11-17", "milliliters": 250}),
    ("exercise", {"day": "2026-11-17", "name": "Walk", "minutes": 10, "intensity": "light"}),
])
def test_each_record_kind(api, key, kind, payload):
    client, _ = api
    headers = bearer(key, str(uuid4()))
    body = draft(kind=kind, payload=payload)
    assert client.post("/v1/sync/operations", json=body, headers=headers).status_code == 200
    response = client.get(f"/v1/records/{kind}/{body['record_id']}", headers=headers)
    assert response.status_code == 200
    assert all(response.json()["payload"][field] == value for field, value in payload.items())

def test_postgres_concurrent_replays_and_stale_edit(api, key):
    from concurrent.futures import ThreadPoolExecutor

    client, engine = api
    if engine.dialect.name != "postgresql":
        pytest.skip("Requires PostgreSQL row locks")
    headers = bearer(key, str(uuid4()))
    assert client.get("/v1/me", headers=headers).status_code == 200
    body = draft()

    def submit(operation):
        return client.post("/v1/sync/operations", json=operation, headers=headers)

    with ThreadPoolExecutor(max_workers=2) as pool:
        first, second = pool.map(submit, (body, body))
        assert first.status_code == second.status_code == 200
        assert first.json() == second.json()
        rid = body["record_id"]
        first, second = pool.map(submit, (draft(rid, "update", 1), draft(rid, "update", 1)))
        assert sorted((first.status_code, second.status_code)) == [200, 409]
        assert client.get(f"/v1/records/weight/{rid}", headers=headers).json()["revision"] == 2

def test_flutter_two_clients_over_tls(api, key, tmp_path):
    if not os.environ.get("FLEX_RUN_FLUTTER_SYNC") or not os.environ.get("FLEX_TEST_POSTGRES_URL"):
        pytest.skip("Opt-in Flutter and isolated PostgreSQL integration")
    import ipaddress
    import shutil
    import socket
    import subprocess
    from datetime import datetime, timedelta, timezone
    from pathlib import Path
    from threading import Thread

    import uvicorn
    from cryptography import x509
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.x509.oid import NameOID

    client, _ = api
    account = token(key, str(uuid4()), expires=int(time.time()) + 300)
    other = token(key, str(uuid4()), expires=int(time.time()) + 300)
    ids = [client.get("/v1/me", headers={"Authorization": f"Bearer {value}"}).json()["id"]
           for value in (account, other)]

    tls_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    subject = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "FLEX disposable test")])
    now = datetime.now(timezone.utc)
    cert = (x509.CertificateBuilder().subject_name(subject).issuer_name(subject)
            .public_key(tls_key.public_key()).serial_number(x509.random_serial_number())
            .not_valid_before(now - timedelta(minutes=1)).not_valid_after(now + timedelta(hours=1))
            .add_extension(x509.SubjectAlternativeName([x509.IPAddress(ipaddress.ip_address("127.0.0.1"))]), False)
            .sign(tls_key, hashes.SHA256()))
    cert_path, key_path = tmp_path / "local.crt", tmp_path / "local.key"
    cert_path.write_bytes(cert.public_bytes(serialization.Encoding.PEM))
    key_path.write_bytes(tls_key.private_bytes(serialization.Encoding.PEM,
        serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))

    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        port = listener.getsockname()[1]
        server = uvicorn.Server(uvicorn.Config(client.app, ssl_certfile=str(cert_path),
            ssl_keyfile=str(key_path), access_log=False, log_level="warning"))
        worker = Thread(target=server.run, kwargs={"sockets": [listener]}, daemon=True)
        worker.start()
        try:
            for _ in range(100):
                if server.started:
                    break
                time.sleep(.05)
            assert server.started, "Disposable TLS server did not start"
            flutter = shutil.which("flutter")
            assert flutter, "Flutter SDK missing"
            env = dict(os.environ, FLEX_TEST_URL=f"https://127.0.0.1:{port}",
                       FLEX_TEST_CERT=str(cert_path), FLEX_TEST_TOKEN=account,
                       FLEX_OTHER_TOKEN=other, FLEX_TEST_ACCOUNT=ids[0], FLEX_OTHER_ACCOUNT=ids[1])
            mobile = Path(__file__).resolve().parents[2] / "mobile"
            result = subprocess.run([flutter, "test", "--no-pub", "--concurrency=1",
                "test/phase15_sync_test.dart"], cwd=mobile, env=env, capture_output=True,
                text=True, timeout=150)
            output = (result.stdout + result.stderr).replace(account, "[redacted]").replace(other, "[redacted]")
            assert result.returncode == 0, output
            print(output)
        finally:
            server.should_exit = True
            worker.join(timeout=10)

def test_account_export_pagination_and_isolation(api, key):
    client, _ = api
    route = "/v1/account/export"
    owner = bearer(key, str(uuid4()))
    other = bearer(key, str(uuid4()))
    assert client.get(route).status_code == 401
    operations = sorted([draft(), draft()], key=lambda op: op["record_id"])
    for operation in operations:
        assert client.post("/v1/sync/operations", headers=owner, json=operation).status_code == 200
    first = client.get(route, headers=owner, params={"limit": 1})
    assert first.headers["cache-control"] == "no-store"
    assert first.headers["x-request-id"]
    first_id = first.json()[0]["id"]
    assert first_id == operations[0]["record_id"]
    second = client.get(route, headers=owner, params={"after_id": first_id})
    assert [record["id"] for record in second.json()] == [operations[1]["record_id"]]
    assert client.get(route, headers=other).json() == []
    invalid = client.get(route, headers=owner, params={"after_id": "private-input"})
    assert invalid.status_code == 422
    assert invalid.json() == {"detail": "invalid_request"}
