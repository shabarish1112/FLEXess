from alembic import op
import sqlalchemy as sa

revision = "0001"
down_revision = None

def upgrade():
    op.create_table("app_user",
                    sa.Column("id", sa.String(36), primary_key=True),
                    sa.Column("identity_subject", sa.String(255), nullable=False, unique=True))

def downgrade():
    op.drop_table("app_user")
