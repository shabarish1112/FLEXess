from alembic import context
from app.config import Settings, make_engine
from app.models import Base

database = make_engine(Settings())
if database is None:
    raise RuntimeError("Set DATABASE_URL before running migrations.")
with database.connect() as connection:
    context.configure(connection=connection, target_metadata=Base.metadata)
    with context.begin_transaction():
        context.run_migrations()
