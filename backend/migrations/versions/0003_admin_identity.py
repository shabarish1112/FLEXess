"""Add identity aliases and administration without rewriting consumer records."""
from alembic import op
import sqlalchemy as sa

revision = "0003"
down_revision = "0002"


def upgrade():
    op.create_table("linked_identity",
                    sa.Column("issuer", sa.String(255), primary_key=True),
                    sa.Column("subject", sa.String(255), primary_key=True),
                    sa.Column("owner_id", sa.String(36), sa.ForeignKey("app_user.id", ondelete="CASCADE"), nullable=False))
    op.create_index("ix_linked_identity_owner_id", "linked_identity", ["owner_id"])
    op.execute("INSERT INTO linked_identity (issuer, subject, owner_id) SELECT identity_issuer, identity_subject, id FROM app_user")
    op.create_table("account_registration",
                    sa.Column("owner_id", sa.String(36), sa.ForeignKey("app_user.id", ondelete="CASCADE"), primary_key=True),
                    sa.Column("registered_at", sa.DateTime(timezone=True), nullable=False))
    op.create_index("ix_account_registration_registered_at", "account_registration", ["registered_at"])
    op.create_table("role_assignment",
                    sa.Column("owner_id", sa.String(36), sa.ForeignKey("app_user.id", ondelete="CASCADE"), primary_key=True),
                    sa.Column("role", sa.String(16), nullable=False),
                    sa.CheckConstraint("role IN ('support', 'admin', 'super_admin')", name="ck_staff_role"))
    op.create_table("audit_event",
                    sa.Column("id", sa.String(36), primary_key=True),
                    sa.Column("actor_id", sa.String(36), nullable=False),
                    sa.Column("action", sa.String(40), nullable=False),
                    sa.Column("target_id", sa.String(36), nullable=False),
                    sa.Column("reason", sa.String(240), nullable=False),
                    sa.Column("created_at", sa.DateTime(timezone=True), nullable=False))
    op.create_index("ix_audit_event_created_at", "audit_event", ["created_at"])
    op.create_table("catalog_food",
                    sa.Column("id", sa.String(36), primary_key=True),
                    sa.Column("name", sa.String(300), nullable=False),
                    sa.Column("normalized_name", sa.String(300), nullable=False),
                    sa.Column("category", sa.String(80), nullable=False),
                    sa.Column("serving_grams", sa.Integer(), nullable=False),
                    sa.Column("nutrients", sa.JSON(), nullable=False),
                    sa.Column("verified", sa.Boolean(), nullable=False),
                    sa.Column("revision", sa.Integer(), nullable=False),
                    sa.CheckConstraint("revision > 0", name="ck_catalog_revision"))
    op.create_index("ix_catalog_food_normalized_name", "catalog_food", ["normalized_name"])


def downgrade():
    # Account links cannot be discarded safely after users have signed in through them.
    raise RuntimeError("Restore a tested pre-migration backup; automated identity unlinking is unsafe")
