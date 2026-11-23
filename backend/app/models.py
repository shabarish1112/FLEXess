from datetime import datetime

from sqlalchemy import JSON, Boolean, CheckConstraint, DateTime, ForeignKey, Integer, String, UniqueConstraint
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


class Base(DeclarativeBase):
    pass


class User(Base):
    __tablename__ = "app_user"
    __table_args__ = (UniqueConstraint("identity_issuer", "identity_subject", name="uq_user_identity"),)
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    identity_subject: Mapped[str] = mapped_column(String(255), nullable=False)
    identity_issuer: Mapped[str] = mapped_column(String(255), nullable=False, server_default="")
    active: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="true")


class LinkedIdentity(Base):
    __tablename__ = "linked_identity"
    issuer: Mapped[str] = mapped_column(String(255), primary_key=True)
    subject: Mapped[str] = mapped_column(String(255), primary_key=True)
    owner_id: Mapped[str] = mapped_column(ForeignKey("app_user.id", ondelete="CASCADE"), index=True)


class AccountRegistration(Base):
    __tablename__ = "account_registration"
    owner_id: Mapped[str] = mapped_column(ForeignKey("app_user.id", ondelete="CASCADE"), primary_key=True)
    registered_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, index=True)


class RoleAssignment(Base):
    __tablename__ = "role_assignment"
    __table_args__ = (CheckConstraint("role IN ('support', 'admin', 'super_admin')", name="ck_staff_role"),)
    owner_id: Mapped[str] = mapped_column(ForeignKey("app_user.id", ondelete="CASCADE"), primary_key=True)
    role: Mapped[str] = mapped_column(String(16), nullable=False)


class AuditEvent(Base):
    __tablename__ = "audit_event"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    actor_id: Mapped[str] = mapped_column(String(36), nullable=False)
    action: Mapped[str] = mapped_column(String(40), nullable=False)
    target_id: Mapped[str] = mapped_column(String(36), nullable=False)
    reason: Mapped[str] = mapped_column(String(240), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, index=True)


class CatalogFood(Base):
    __tablename__ = "catalog_food"
    __table_args__ = (CheckConstraint("revision > 0", name="ck_catalog_revision"),)
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    name: Mapped[str] = mapped_column(String(300), nullable=False)
    normalized_name: Mapped[str] = mapped_column(String(300), nullable=False, index=True)
    category: Mapped[str] = mapped_column(String(80), nullable=False)
    serving_grams: Mapped[int] = mapped_column(Integer, nullable=False)
    nutrients: Mapped[dict] = mapped_column(JSON, nullable=False)
    verified: Mapped[bool] = mapped_column(Boolean, nullable=False)
    revision: Mapped[int] = mapped_column(Integer, nullable=False)


class OwnedRecord(Base):
    __tablename__ = "owned_record"
    __table_args__ = (CheckConstraint("revision > 0", name="ck_record_revision"),)
    owner_id: Mapped[str] = mapped_column(ForeignKey("app_user.id", ondelete="CASCADE"), primary_key=True)
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    kind: Mapped[str] = mapped_column(String(16), nullable=False)
    payload: Mapped[dict] = mapped_column(JSON, nullable=False)
    revision: Mapped[int] = mapped_column(Integer, nullable=False)
    deleted: Mapped[bool] = mapped_column(Boolean, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)


class SyncReceipt(Base):
    __tablename__ = "sync_receipt"
    __table_args__ = (UniqueConstraint("owner_id", "sequence", name="uq_receipt_sequence"),)
    owner_id: Mapped[str] = mapped_column(ForeignKey("app_user.id", ondelete="CASCADE"), primary_key=True)
    operation_id: Mapped[str] = mapped_column(String(36), primary_key=True)
    sequence: Mapped[int] = mapped_column(Integer, nullable=False)
    fingerprint: Mapped[str] = mapped_column(String(64), nullable=False)
    result: Mapped[dict] = mapped_column(JSON, nullable=False)
