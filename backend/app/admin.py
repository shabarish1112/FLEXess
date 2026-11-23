from datetime import datetime, timedelta, timezone
from typing import Annotated, Literal
from uuid import UUID, uuid4

from fastapi import Depends, HTTPException, Query, Request
from pydantic import Field
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError

from .access import recent_identity
from .identity import InvalidIdentity
from .models import AccountRegistration, AuditEvent, CatalogFood, LinkedIdentity, OwnedRecord, RoleAssignment, User
from pydantic import BaseModel, ConfigDict


class Input(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)


class LinkInput(Input):
    token: str = Field(min_length=1, max_length=8192, repr=False)


class StatusInput(Input):
    active: bool = Field(strict=True)
    reason: str = Field(min_length=8, max_length=240)


class FoodInput(Input):
    name: str = Field(min_length=1, max_length=300)
    category: str = Field(min_length=1, max_length=80)
    serving_grams: int = Field(strict=True, ge=1, le=100000)
    energy_kcal: int = Field(strict=True, ge=0, le=10000)
    protein_mg: int = Field(strict=True, ge=0, le=100000)
    carbs_mg: int = Field(strict=True, ge=0, le=100000)
    fat_mg: int = Field(strict=True, ge=0, le=100000)
    verified: bool = False
    revision: int = Field(strict=True, ge=0)


class FoodImport(Input):
    items: list[FoodInput] = Field(min_length=1, max_length=50)


class DeleteFood(Input):
    revision: int = Field(strict=True, ge=1)
    reason: str = Field(min_length=8, max_length=240)


def audit(db, user, action, target, reason):
    db.add(AuditEvent(id=str(uuid4()), actor_id=user.id, action=action,
                      target_id=target, reason=reason, created_at=datetime.now(timezone.utc)))


def register_admin(app, session, owner, verifier):
    Db = Annotated[object, Depends(session)]
    Owner = Annotated[User, Depends(owner)]

    def staff(user: Owner, db: Db):
        assignment = db.get(RoleAssignment, user.id)
        if assignment is None:
            raise HTTPException(403, "staff_access_required")
        return assignment.role

    Staff = Annotated[str, Depends(staff)]

    def require_admin(role):
        if role not in ("admin", "super_admin"):
            raise HTTPException(403, "admin_access_required")

    @app.post("/v1/account/link")
    def link(body: LinkInput, request: Request, user: Owner, db: Db):
        recent_identity(request.state.identity)
        try:
            other = verifier.verify(body.token)
        except InvalidIdentity:
            raise HTTPException(401, "invalid_link_credential") from None
        recent_identity(other)
        alias = db.get(LinkedIdentity, (other.issuer, other.subject))
        existing = db.scalar(select(User).where(User.identity_issuer == other.issuer,
                                               User.identity_subject == other.subject))
        if (alias and alias.owner_id != user.id) or (existing and existing.id != user.id):
            raise HTTPException(409, "identity_already_has_account")
        if not alias:
            db.add(LinkedIdentity(issuer=other.issuer, subject=other.subject, owner_id=user.id))
            audit(db, user, "identity_linked", user.id, "Both credential owners verified")
            try:
                db.commit()
            except IntegrityError:
                db.rollback()
                raise HTTPException(409, "identity_already_has_account") from None
        return {"id": user.id}

    @app.get("/v1/admin/me")
    def me(user: Owner, role: Staff):
        return {"id": user.id, "role": role}

    @app.get("/v1/catalog")
    def consumer_catalog(user: Owner, db: Db, q: str = Query("", max_length=100),
                         limit: int = Query(50, ge=1, le=100)):
        rows = db.scalars(select(CatalogFood).where(CatalogFood.verified.is_(True),
            CatalogFood.normalized_name.contains(q.casefold(), autoescape=True)).order_by(CatalogFood.normalized_name).limit(limit))
        return {"items": [{"id": row.id, "name": row.name, "serving_grams": row.serving_grams,
                           "revision": row.revision, **row.nutrients} for row in rows]}

    @app.get("/v1/admin/overview")
    def overview(role: Staff, db: Db, days: int = Query(30, ge=1, le=366)):
        since = datetime.now(timezone.utc) - timedelta(days=days)
        count = lambda model: db.scalar(select(func.count()).select_from(model))
        registrations = db.scalar(select(func.count()).select_from(AccountRegistration).where(
            AccountRegistration.registered_at >= since))
        activity = dict(db.execute(select(OwnedRecord.kind, func.count()).where(
            OwnedRecord.updated_at >= since, OwnedRecord.deleted.is_(False)).group_by(OwnedRecord.kind)).all())
        growth = [{"day": str(day), "registrations": total} for day, total in db.execute(select(
            func.date(AccountRegistration.registered_at), func.count()).where(
                AccountRegistration.registered_at >= since).group_by(func.date(AccountRegistration.registered_at)).order_by(
                    func.date(AccountRegistration.registered_at)))]
        return {"days": days, "users": count(User), "enabled_accounts": db.scalar(select(func.count()).select_from(User).where(User.active.is_(True))),
                "new_registrations": registrations, "legacy_registration_unknown": count(User) - count(AccountRegistration),
                "catalog_foods": count(CatalogFood), "activity": activity, "growth": growth,
                "identity_issuers": [{"issuer": issuer, "identities": total} for issuer, total in db.execute(
                    select(LinkedIdentity.issuer, func.count()).group_by(LinkedIdentity.issuer))],
                "unavailable": ["retention", "platform_usage", "api_error_trends", "background_jobs"],
                "definitions": {"users": "All backend accounts, including suspended accounts",
                                "enabled_accounts": "Accounts permitted to authenticate; not daily active users",
                                "new_registrations": "Accounts created since registration instrumentation began, within range",
                                "activity": "Current nondeleted records whose last server update falls in range; not event counts"}}

    @app.get("/v1/admin/users")
    def users(role: Staff, db: Db, q: str = Query("", max_length=36),
              offset: int = Query(0, ge=0, le=1000000), limit: int = Query(25, ge=1, le=100)):
        query = select(User).where(User.id.contains(q, autoescape=True))
        rows = list(db.scalars(query.order_by(User.id).offset(offset).limit(limit)))
        ids = [row.id for row in rows]
        roles = dict(db.execute(select(RoleAssignment.owner_id, RoleAssignment.role).where(RoleAssignment.owner_id.in_(ids))).all())
        dates = dict(db.execute(select(AccountRegistration.owner_id, AccountRegistration.registered_at).where(AccountRegistration.owner_id.in_(ids))).all())
        providers = {}
        for alias in db.scalars(select(LinkedIdentity).where(LinkedIdentity.owner_id.in_(ids))):
            providers.setdefault(alias.owner_id, []).append(alias.issuer)
        return {"total": db.scalar(select(func.count()).select_from(query.subquery())), "items": [
            {"id": row.id, "active": row.active, "role": roles.get(row.id, "user"),
             "registered_at": dates.get(row.id), "issuers": providers.get(row.id, [row.identity_issuer])} for row in rows]}

    @app.post("/v1/admin/users/{account_id}/status")
    def status(account_id: UUID, body: StatusInput, request: Request, user: Owner, role: Staff, db: Db):
        require_admin(role)
        recent_identity(request.state.identity)
        target = db.get(User, str(account_id), with_for_update=True)
        if target is None:
            raise HTTPException(404, "account_not_found")
        if target.id == user.id or db.get(RoleAssignment, target.id) is not None:
            raise HTTPException(403, "staff_status_requires_trusted_process")
        target.active = body.active
        audit(db, user, "account_enabled" if body.active else "account_suspended", target.id, body.reason)
        db.commit()
        return {"id": target.id, "active": target.active}

    @app.get("/v1/admin/catalog")
    def catalog(role: Staff, db: Db, q: str = Query("", max_length=100),
                offset: int = Query(0, ge=0, le=1000000), limit: int = Query(25, ge=1, le=100)):
        query = select(CatalogFood).where(CatalogFood.normalized_name.contains(q.casefold(), autoescape=True))
        duplicates = set(db.scalars(select(CatalogFood.normalized_name).group_by(CatalogFood.normalized_name).having(func.count() > 1)))
        return {"total": db.scalar(select(func.count()).select_from(query.subquery())), "items": [
            {"id": row.id, "name": row.name, "category": row.category, "serving_grams": row.serving_grams,
             **row.nutrients, "verified": row.verified, "revision": row.revision,
             "possible_duplicate": row.normalized_name in duplicates}
            for row in db.scalars(query.order_by(CatalogFood.normalized_name, CatalogFood.id).offset(offset).limit(limit))]}

    @app.post("/v1/admin/catalog/import")
    def import_food(body: FoodImport, request: Request, user: Owner, role: Staff, db: Db):
        require_admin(role)
        recent_identity(request.state.identity)
        if any(item.revision != 0 for item in body.items):
            raise HTTPException(422, "imports_require_new_records")
        ids = []
        for item in body.items:
            identifier = str(uuid4())
            db.add(CatalogFood(id=identifier, name=item.name, normalized_name=" ".join(item.name.casefold().split()),
                               category=item.category, serving_grams=item.serving_grams,
                               nutrients=item.model_dump(include={"energy_kcal", "protein_mg", "carbs_mg", "fat_mg"}),
                               verified=item.verified, revision=1))
            ids.append(identifier)
        audit(db, user, "catalog_imported", user.id, f"Imported {len(ids)} food records")
        db.commit()
        return {"ids": ids, "imported": len(ids)}

    @app.post("/v1/admin/catalog/{food_id}/delete")
    def delete_food(food_id: UUID, body: DeleteFood, request: Request, user: Owner, role: Staff, db: Db):
        require_admin(role)
        recent_identity(request.state.identity)
        row = db.get(CatalogFood, str(food_id), with_for_update=True)
        if row is None:
            raise HTTPException(404, "food_not_found")
        if row.revision != body.revision:
            raise HTTPException(409, "catalog_revision_conflict")
        db.delete(row)
        audit(db, user, "catalog_deleted", str(food_id), body.reason)
        db.commit()
        return {"id": str(food_id), "deleted": True}

    @app.post("/v1/admin/catalog/{food_id}")
    def save_food(food_id: UUID, body: FoodInput, request: Request, user: Owner, role: Staff, db: Db):
        require_admin(role)
        recent_identity(request.state.identity)
        row = db.get(CatalogFood, str(food_id), with_for_update=True)
        if (row is None and body.revision != 0) or (row and row.revision != body.revision):
            raise HTTPException(409, "catalog_revision_conflict")
        if row is None:
            row = CatalogFood(id=str(food_id))
            db.add(row)
        row.name, row.normalized_name = body.name, " ".join(body.name.casefold().split())
        row.category, row.serving_grams = body.category, body.serving_grams
        row.nutrients = body.model_dump(include={"energy_kcal", "protein_mg", "carbs_mg", "fat_mg"})
        row.verified, row.revision = body.verified, body.revision + 1
        audit(db, user, "catalog_saved", row.id, "Verified" if row.verified else "Draft")
        try:
            db.commit()
        except IntegrityError:
            db.rollback()
            raise HTTPException(409, "catalog_revision_conflict") from None
        return {"id": row.id, "revision": row.revision}

    @app.get("/v1/admin/audit")
    def events(role: Staff, db: Db, offset: int = Query(0, ge=0, le=1000000), limit: int = Query(25, ge=1, le=100)):
        require_admin(role)
        return {"items": [{"id": row.id, "actor_id": row.actor_id, "action": row.action,
                           "target_id": row.target_id, "reason": row.reason, "created_at": row.created_at}
                          for row in db.scalars(select(AuditEvent).order_by(AuditEvent.created_at.desc(), AuditEvent.id).offset(offset).limit(limit))]}
