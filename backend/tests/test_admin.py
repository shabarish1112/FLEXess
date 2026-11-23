import time
from types import SimpleNamespace
from uuid import uuid4

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, select
from sqlalchemy.orm import Session

from app.config import Settings
from app.identity import ConfiguredIdentityVerifier, FirebaseIdentityVerifier, InvalidIdentity, ManagedIdentityVerifier
from app.main import create_app
from app.models import AuditEvent, Base, RoleAssignment
from app.access import IdentityRateLimit
from app.identity import Identity
from fastapi import HTTPException


@pytest.fixture
def api(tmp_path):
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    firebase = FirebaseIdentityVerifier("flex-fitness-98e76")
    legacy = ManagedIdentityVerifier("https://legacy.invalid/", "urn:flex", "https://legacy.invalid/jwks", "native")
    for verifier in (firebase, legacy):
        verifier.keys = SimpleNamespace(get_signing_key_from_jwt=lambda _: SimpleNamespace(key=key.public_key()))
    url = f"sqlite:///{tmp_path / 'admin.sqlite'}"
    engine = create_engine(url)
    Base.metadata.create_all(engine)
    def token(subject, *, old=False, **claims):
        now = int(time.time())
        return jwt.encode({"iss": legacy.issuer if old else firebase.issuer,
                           "aud": "urn:flex" if old else firebase.project_id,
                           "sub": subject, "exp": now + 3600, "iat": now, "auth_time": now,
                           **({"jti": str(uuid4()), "client_id": "native"} if old else {}), **claims},
                          key, algorithm="RS256", headers={"kid": "test", "typ": "at+jwt" if old else "JWT"})
    with TestClient(create_app(Settings(database_url=url), verifier=ConfiguredIdentityVerifier([legacy, firebase]))) as client:
        yield client, engine, token, firebase
    engine.dispose()


def headers(token):
    return {"Authorization": f"Bearer {token}"}


def test_rate_limit_is_identity_scoped_bounded_and_resets(monkeypatch):
    limiter = IdentityRateLimit()
    monkeypatch.setattr('app.access.monotonic', lambda: 1)
    identity = Identity('https://issuer.invalid/', 'one')
    for _ in range(240):
        limiter.check(identity)
    with pytest.raises(HTTPException) as error:
        limiter.check(identity)
    assert error.value.status_code == 429
    limiter.check(Identity(identity.issuer, 'two'))
    monkeypatch.setattr('app.access.monotonic', lambda: 61)
    limiter.check(identity)
    for i in range(10001):
        limiter.check(Identity(identity.issuer, str(i)))
    assert len(limiter.requests) == 10000


def staff(api, role="admin"):
    client, engine, token, _ = api
    auth = headers(token(str(uuid4())))
    account = client.get("/v1/me", headers=auth).json()["id"]
    with Session(engine) as db, db.begin():
        db.add(RoleAssignment(owner_id=account, role=role))
    return auth


def test_firebase_claims_are_verified(api):
    _, _, token, verifier = api
    assert verifier.verify(token("firebase-user")).subject == "firebase-user"
    for claims in ({"aud": "another-project"}, {"iss": "https://securetoken.google.com/another-project"},
                   {"auth_time": int(time.time()) + 120}, {"auth_time": True}, {"sub": ""},
                   {"sub": "x" * 129}, {"exp": 1}, {"aud": ["flex-fitness-98e76"]}):
        with pytest.raises(InvalidIdentity):
            verifier.verify(token("user", **claims))


def test_untrusted_issuer_cannot_select_arbitrary_keys(api):
    _, _, token, firebase = api
    composite = ConfiguredIdentityVerifier([firebase])
    firebase.keys = SimpleNamespace(get_signing_key_from_jwt=lambda _: pytest.fail("Unknown issuer must not fetch keys"))
    with pytest.raises(InvalidIdentity):
        composite.verify(token("user", iss="https://attacker.invalid/"))


def test_roles_and_privacy(api):
    client, _, token, _ = api
    consumer = headers(token("consumer"))
    assert client.get("/v1/admin/overview").status_code == 401
    for path in ("me", "overview", "users", "catalog", "audit"):
        assert client.get(f"/v1/admin/{path}", headers=consumer).status_code == 403
    support = staff(api, "support")
    assert client.get("/v1/admin/overview", headers=support).status_code == 200
    assert client.get("/v1/admin/audit", headers=support).status_code == 403
    directory = client.get("/v1/admin/users", headers=support).json()
    assert directory["total"] == 2
    assert set(directory["items"][0]) == {"id", "active", "role", "registered_at", "issuers"}
    assert client.get("/v1/records/diary", headers=support).json() == []


def test_link_preserves_account_and_rejects_merge(api):
    client, _, token, _ = api
    legacy = headers(token("existing-user", old=True))
    account = client.get("/v1/me", headers=legacy).json()
    record = str(uuid4())
    assert client.post("/v1/sync/operations", headers=legacy, json={
        "operation_id": str(uuid4()), "record_id": record, "kind": "weight", "action": "create",
        "base_revision": 0, "payload_version": 1, "payload": {"day": "2026-11-20", "grams": 70000}}).status_code == 200
    firebase = token("new-firebase-user")
    assert client.post("/v1/account/link", headers=legacy, json={"token": firebase}).json() == account
    assert client.get("/v1/me", headers=headers(firebase)).json() == account
    assert client.get(f"/v1/records/weight/{record}", headers=headers(firebase)).json()["payload"]["grams"] == 70000
    other = token("already-registered")
    client.get("/v1/me", headers=headers(other))
    assert client.post("/v1/account/link", headers=legacy, json={"token": other}).status_code == 409
    stale = headers(token("existing-user", old=True, auth_time=1))
    assert client.post("/v1/account/link", headers=stale, json={"token": token("another")}).status_code == 403


def test_catalog_suspension_and_audit(api):
    client, engine, token, _ = api
    admin = staff(api)
    consumer = headers(token("customer"))
    account = client.get("/v1/me", headers=consumer).json()["id"]
    food = str(uuid4())
    body = {"name": "Apple", "category": "Fruit", "serving_grams": 100, "energy_kcal": 52,
            "protein_mg": 300, "carbs_mg": 14000, "fat_mg": 200, "verified": True, "revision": 0}
    route = f"/v1/admin/catalog/{food}"
    assert client.post(route, headers=consumer, json=body).status_code == 403
    assert client.post(route, headers=admin, json=body).json()["revision"] == 1
    assert client.post(route, headers=admin, json=body).status_code == 409
    assert client.get("/v1/admin/catalog", headers=admin).json()["items"][0]["name"] == "Apple"
    assert client.get("/v1/catalog", headers=consumer).json()["items"][0]["name"] == "Apple"
    status = client.post(f"/v1/admin/users/{account}/status", headers=admin,
                         json={"active": False, "reason": "Account abuse review"})
    assert status.status_code == 200
    assert client.get("/v1/me", headers=consumer).status_code == 403
    with Session(engine) as db:
        assert len(list(db.scalars(select(AuditEvent)))) == 2
    overview = client.get("/v1/admin/overview", headers=admin).json()
    assert overview["catalog_foods"] == 1
    assert overview["enabled_accounts"] == 1


def test_import_is_atomic_and_delete_checks_revision(api):
    client, _, _, _ = api
    auth = staff(api)
    food = {"name": "Oats", "category": "Grains", "serving_grams": 40, "energy_kcal": 380,
            "protein_mg": 13000, "carbs_mg": 68000, "fat_mg": 7000, "revision": 0}
    response = client.post("/v1/admin/catalog/import", headers=auth, json={"items": [food, {**food, "energy_kcal": -1}]})
    assert response.status_code == 422
    assert client.get("/v1/admin/catalog", headers=auth).json()["total"] == 0
    result = client.post("/v1/admin/catalog/import", headers=auth, json={"items": [food, food]}).json()
    assert result["imported"] == 2
    rows = client.get("/v1/admin/catalog", headers=auth).json()["items"]
    assert all(row["possible_duplicate"] for row in rows)
    route = f"/v1/admin/catalog/{result['ids'][0]}/delete"
    assert client.post(route, headers=auth, json={"revision": 2, "reason": "Duplicate reviewed"}).status_code == 409
    assert client.post(route, headers=auth, json={"revision": 1, "reason": "Duplicate reviewed"}).status_code == 200


def test_stale_staff_cannot_mutate_or_self_suspend(api):
    client, _, token, _ = api
    auth = staff(api)
    account = client.get("/v1/admin/me", headers=auth).json()["id"]
    assert client.post(f"/v1/admin/users/{account}/status", headers=auth,
                       json={"active": False, "reason": "Attempt self suspension"}).status_code == 403
    subject = "stale-admin"
    fresh = headers(token(subject))
    identifier = client.get("/v1/me", headers=fresh).json()["id"]
    with Session(api[1]) as db, db.begin():
        db.add(RoleAssignment(owner_id=identifier, role="admin"))
    assert client.post("/v1/admin/catalog/import", headers=headers(token(subject, auth_time=1)),
                       json={"items": [{"name": "Food", "category": "Test", "serving_grams": 100,
                                        "energy_kcal": 1, "protein_mg": 1, "carbs_mg": 1, "fat_mg": 1, "revision": 0}]}).status_code == 403


def test_trusted_role_command_requires_existing_account_and_audits(api, monkeypatch):
    from app.manage_roles import main
    client, engine, token, _ = api
    account = client.get("/v1/me", headers=headers(token("operator-assigned"))).json()["id"]
    monkeypatch.setenv("DATABASE_URL", str(engine.url))
    monkeypatch.setattr("sys.argv", ["manage_roles", str(uuid4()), "admin", "--reason", "Approved access ticket"])
    with pytest.raises(SystemExit):
        main()
    monkeypatch.setattr("sys.argv", ["manage_roles", account, "admin", "--reason", "Approved access ticket"])
    main()
    with Session(engine) as db:
        assert db.get(RoleAssignment, account).role == "admin"
        assert db.scalar(select(AuditEvent).where(AuditEvent.actor_id == "trusted-database-operator")) is not None
