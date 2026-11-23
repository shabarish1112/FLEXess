from datetime import datetime, timezone
from typing import Annotated
from uuid import uuid4
import time
from time import monotonic
from collections import OrderedDict
from threading import Lock

from fastapi import Depends, HTTPException, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from .identity import InvalidIdentity
from .models import AccountRegistration, LinkedIdentity, User


class IdentityRateLimit:
    # shortcut: process-local limits reset on restart; use shared limits before adding workers.
    def __init__(self):
        self.requests = OrderedDict()
        self.lock = Lock()

    def check(self, identity):
        key = (identity.issuer, identity.subject)
        window = int(monotonic() // 60)
        with self.lock:
            previous, count = self.requests.get(key, (window, 0))
            count = count if previous == window else 0
            if count >= 240:
                raise HTTPException(429, "request_limit_exceeded", headers={"Retry-After": "60"})
            self.requests[key] = (window, count + 1)
            self.requests.move_to_end(key)
            if len(self.requests) > 10000:
                self.requests.popitem(last=False)


def recent_identity(identity):
    when = identity.authenticated_at
    if type(when) is not int or not 0 <= time.time() - when <= 300:
        raise HTTPException(403, "recent_authentication_required")


def dependencies(engine, verifier):
    bearer = HTTPBearer(auto_error=False)
    limiter = IdentityRateLimit()

    def session():
        with Session(engine, expire_on_commit=False) as db:
            yield db

    def owner(request: Request,
              auth: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)],
              db: Annotated[Session, Depends(session)]) -> User:
        if auth is None:
            raise HTTPException(401, "authentication_required", headers={"WWW-Authenticate": "Bearer"})
        if verifier is None:
            raise HTTPException(503, "identity_not_configured")
        try:
            identity = verifier.verify(auth.credentials)
        except InvalidIdentity:
            raise HTTPException(401, "invalid_access_token", headers={"WWW-Authenticate": "Bearer"}) from None
        request.state.identity = identity
        limiter.check(identity)
        key = (identity.issuer, identity.subject)
        alias = db.get(LinkedIdentity, key)
        user = db.get(User, alias.owner_id) if alias else db.scalar(select(User).where(
            User.identity_issuer == identity.issuer, User.identity_subject == identity.subject))
        if alias is None:
            try:
                with db.begin_nested():
                    if user is None:
                        user = User(id=str(uuid4()), identity_issuer=identity.issuer,
                                    identity_subject=identity.subject, active=True)
                        db.add(user)
                        db.flush()
                        db.add(AccountRegistration(owner_id=user.id, registered_at=datetime.now(timezone.utc)))
                    db.add(LinkedIdentity(issuer=identity.issuer, subject=identity.subject, owner_id=user.id))
                    db.flush()
                db.commit()
            except IntegrityError:
                alias = db.get(LinkedIdentity, key)
                if alias is None:
                    raise
                user = db.get(User, alias.owner_id)
        if user is None or not user.active:
            raise HTTPException(403, "account_disabled")
        return user

    return session, owner
