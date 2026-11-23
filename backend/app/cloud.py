from datetime import date, datetime, timezone
from hashlib import sha256
import json
from typing import Annotated, Literal
from uuid import UUID, uuid4

from fastapi import Depends, FastAPI, HTTPException, Query
from pydantic import BaseModel, ConfigDict, Field, ValidationError, model_validator
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from .identity import IdentityVerifier
from .models import OwnedRecord, SyncReceipt, User
from .access import dependencies
from .admin import register_admin

Kind = Literal["profile", "goals", "diary", "weight", "water", "exercise"]
TargetMg = Annotated[int, Field(strict=True, ge=1000, le=2000000, multiple_of=1000)]
Nutrient = Annotated[int, Field(strict=True, ge=0, le=100_000_000)]


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class Profile(StrictModel):
    display_name: str = Field(min_length=1, max_length=120)


class Goals(StrictModel):
    day: date
    calories: Annotated[int, Field(strict=True, ge=1, le=20000)] | None
    protein_mg: TargetMg | None = None
    carbs_mg: TargetMg | None = None
    fat_mg: TargetMg | None = None
    water_ml: Annotated[int, Field(strict=True, ge=1, le=20000)] | None = None
    weight_grams: Annotated[int, Field(strict=True, ge=1000, le=1000000)] | None = None
    exercise_credit: bool | None = None


class Diary(StrictModel):
    day: date
    meal: Literal["breakfast", "lunch", "dinner", "snacks"]
    name: str = Field(min_length=1, max_length=300)
    serving: str = Field(min_length=1, max_length=120)
    quantity_milli: Annotated[int, Field(strict=True, ge=1, le=100000)]
    nutrients: dict[Literal["energy", "protein", "carbs", "fat", "fiber"], Nutrient | None]
    serving_grams: float | None = Field(default=None, gt=0, le=100000, allow_inf_nan=False)
    per_100g: dict[Literal["energy", "protein", "carbs", "fat", "fiber"], Nutrient | None] | None = None

    @model_validator(mode="after")
    def paired_serving_metadata(self):
        if (self.serving_grams is None) != (self.per_100g is None):
            raise ValueError("Serving weight and nutrient density must be supplied together")
        return self


class Weight(StrictModel):
    day: date
    grams: Annotated[int, Field(strict=True, ge=1000, le=1000000)]


class Water(StrictModel):
    day: date
    milliliters: Annotated[int, Field(strict=True, ge=1, le=20000)]


class Exercise(StrictModel):
    day: date
    name: str = Field(min_length=1, max_length=80, pattern=r"\S")
    minutes: int = Field(strict=True, ge=1, le=1440)
    intensity: Literal["light", "moderate", "vigorous"] | None = None
    category: str | None = Field(default=None, max_length=80)
    energy_kcal: Nutrient | None = None


PAYLOADS = {"profile": Profile, "goals": Goals, "diary": Diary,
            "weight": Weight, "water": Water, "exercise": Exercise}


class Operation(StrictModel):
    operation_id: UUID
    record_id: UUID
    kind: Kind
    action: Literal["create", "update", "delete"]
    base_revision: int = Field(strict=True, ge=0, lt=2_000_000_000)
    payload_version: Literal[1]
    payload: dict | None = None


class Record(BaseModel):
    id: UUID
    kind: Kind
    revision: int
    deleted: bool
    payload: dict | None
    updated_at: datetime


class Ack(BaseModel):
    operation_id: UUID
    sequence: int
    record: Record


class Account(BaseModel):
    id: UUID


def record_view(row: OwnedRecord) -> Record:
    return Record(id=row.id, kind=row.kind, revision=row.revision,
                  deleted=row.deleted, payload=None if row.deleted else row.payload,
                  updated_at=row.updated_at)


def register_cloud(app: FastAPI, engine, verifier: IdentityVerifier | None) -> None:
    session, owner = dependencies(engine, verifier)
    register_admin(app, session, owner, verifier)

    Db = Annotated[Session, Depends(session)]
    Owner = Annotated[User, Depends(owner)]

    @app.get("/v1/me", response_model=Account)
    def me(user: Owner):
        return Account(id=user.id)

    @app.get("/v1/account/export", response_model=list[Record])
    def export_account_records(user: Owner, db: Db, after_id: UUID | None = None,
                               limit: int = Query(50, ge=1, le=100)):
        query = select(OwnedRecord).where(OwnedRecord.owner_id == user.id)
        if after_id is not None:
            query = query.where(OwnedRecord.id > str(after_id))
        return [record_view(row) for row in db.scalars(query.order_by(OwnedRecord.id).limit(limit))]

    @app.get("/v1/records/{kind}", response_model=list[Record])
    def list_records(kind: Kind, user: Owner, db: Db,
                     after_id: UUID | None = None, limit: int = Query(50, ge=1, le=100)):
        query = select(OwnedRecord).where(OwnedRecord.owner_id == user.id,
                                          OwnedRecord.kind == kind, OwnedRecord.deleted.is_(False))
        if after_id is not None:
            query = query.where(OwnedRecord.id > str(after_id))
        return [record_view(row) for row in db.scalars(query.order_by(OwnedRecord.id).limit(limit))]

    @app.get("/v1/records/{kind}/{record_id}", response_model=Record)
    def get_record(kind: Kind, record_id: UUID, user: Owner, db: Db):
        row = db.get(OwnedRecord, (user.id, str(record_id)))
        if row is None or row.kind != kind or row.deleted:
            raise HTTPException(404, "record_not_found")
        return record_view(row)

    @app.get("/v1/sync/changes", response_model=list[Ack])
    def changes(user: Owner, db: Db, after: int = Query(0, ge=0),
                limit: int = Query(50, ge=1, le=100)):
        return [receipt.result for receipt in db.scalars(
            select(SyncReceipt).where(SyncReceipt.owner_id == user.id, SyncReceipt.sequence > after)
            .order_by(SyncReceipt.sequence).limit(limit))]

    @app.post("/v1/sync/operations", response_model=Ack)
    def submit(operation: Operation, user: Owner, db: Db):
        if (operation.action == "delete") != (operation.payload is None):
            raise HTTPException(422, "invalid_payload")
        payload = None
        if operation.payload is not None:
            try:
                payload = PAYLOADS[operation.kind].model_validate(operation.payload).model_dump(mode="json")
                for field in {"goals": ("water_ml", "weight_grams", "exercise_credit"),
                              "exercise": ("category", "energy_kcal")}.get(operation.kind, ()):
                    if payload[field] is None:
                        del payload[field]
                if operation.kind == "diary":
                    for field in ("serving_grams", "per_100g"):
                        if payload[field] is None:
                            del payload[field]
            except ValidationError:
                raise HTTPException(422, "invalid_payload") from None
        body = operation.model_dump(mode="json")
        body["payload"] = payload
        fingerprint = sha256(json.dumps(body, sort_keys=True).encode()).hexdigest()
        # PostgreSQL serializes the receipts and revisions for this owner.
        locked = db.scalar(select(User).where(User.id == user.id).with_for_update().execution_options(populate_existing=True))
        if locked is None or not locked.active:
            raise HTTPException(403, "account_disabled")
        receipt = db.get(SyncReceipt, (user.id, str(operation.operation_id)))
        if receipt is not None:
            if receipt.fingerprint != fingerprint:
                raise HTTPException(409, "operation_id_reused")
            return receipt.result

        row = db.get(OwnedRecord, (user.id, str(operation.record_id)))
        now = datetime.now(timezone.utc)
        if operation.action == "create":
            if row is not None or operation.base_revision != 0:
                raise HTTPException(409, "create_conflict")
            row = OwnedRecord(owner_id=user.id, id=str(operation.record_id), kind=operation.kind,
                              revision=1, payload=payload, deleted=False, created_at=now, updated_at=now)
            db.add(row)
        else:
            if row is None or row.kind != operation.kind:
                raise HTTPException(404, "record_not_found")
            if row.deleted or row.revision != operation.base_revision:
                raise HTTPException(409, {"code": "revision_conflict", "current": record_view(row).model_dump(mode="json")})
            row.revision += 1
            row.updated_at = now
            row.deleted = operation.action == "delete"
            row.payload = payload if payload is not None else {}

        sequence = (db.scalar(select(func.max(SyncReceipt.sequence)).where(SyncReceipt.owner_id == user.id)) or 0) + 1
        result = Ack(operation_id=operation.operation_id, sequence=sequence, record=record_view(row))
        db.add(SyncReceipt(owner_id=user.id, operation_id=str(operation.operation_id),
                           sequence=sequence, fingerprint=fingerprint, result=result.model_dump(mode="json")))
        # Commit before reporting success, including when the response is lost.
        db.commit()
        return result
