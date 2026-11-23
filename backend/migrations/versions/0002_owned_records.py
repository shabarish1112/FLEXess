"""Add issuer-scoped users, owned records and durable acknowledgements."""

from alembic import op
import sqlalchemy as sa

revision = "0002"
down_revision = "0001"


def upgrade():
    # The first revision used an unnamed unique constraint. Name it during reflection.
    convention = {"uq": "uq_%(table_name)s_%(column_0_name)s"}
    with op.batch_alter_table("app_user", naming_convention=convention) as batch:
        batch.add_column(sa.Column("identity_issuer", sa.String(255), nullable=False, server_default=""))
        batch.add_column(sa.Column("active", sa.Boolean(), nullable=False, server_default=sa.true()))
        name = "app_user_identity_subject_key" if op.get_bind().dialect.name == "postgresql" else "uq_app_user_identity_subject"
        batch.drop_constraint(name, type_="unique")
        batch.create_unique_constraint("uq_user_identity", ["identity_issuer", "identity_subject"])
    op.create_table(
        "owned_record",
        sa.Column("owner_id", sa.String(36), sa.ForeignKey("app_user.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("id", sa.String(36), primary_key=True),
        sa.Column("kind", sa.String(16), nullable=False),
        sa.Column("payload", sa.JSON(), nullable=False),
        sa.Column("revision", sa.Integer(), nullable=False),
        sa.Column("deleted", sa.Boolean(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint("revision > 0", name="ck_record_revision"),
    )
    op.create_table(
        "sync_receipt",
        sa.Column("owner_id", sa.String(36), sa.ForeignKey("app_user.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("operation_id", sa.String(36), primary_key=True),
        sa.Column("sequence", sa.Integer(), nullable=False),
        sa.Column("fingerprint", sa.String(64), nullable=False),
        sa.Column("result", sa.JSON(), nullable=False),
        sa.UniqueConstraint("owner_id", "sequence", name="uq_receipt_sequence"),
    )


def downgrade():
    op.drop_table("sync_receipt")
    op.drop_table("owned_record")
    with op.batch_alter_table("app_user") as batch:
        batch.drop_constraint("uq_user_identity", type_="unique")
        name = "app_user_identity_subject_key" if op.get_bind().dialect.name == "postgresql" else "uq_app_user_identity_subject"
        batch.create_unique_constraint(name, ["identity_subject"])
        batch.drop_column("active")
        batch.drop_column("identity_issuer")
