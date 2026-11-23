"""Provision a new FLEX database using an ignored, server-only JSON configuration."""
import argparse
import json
import os
from pathlib import Path
import secrets
import sys

import certifi
import psycopg
from psycopg import sql
from alembic import command
from alembic.config import Config
from sqlalchemy.engine import make_url


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("config", type=Path)
    parser.add_argument("--environment", choices=("staging", "production"), required=True)
    args = parser.parse_args()
    path = args.config.resolve()
    settings = json.loads(path.read_text())
    owner = make_url(settings["OWNER_DATABASE_URL"])
    owner = owner.set(host=owner.host.replace("-pooler.", "."))
    if not owner.host.endswith(".neon.tech") or owner.database != "flex" or owner.username != "flex_owner":
        raise ValueError("Expected the explicitly provisioned FLEX Neon database owner")
    ca = certifi.where()
    connection = owner.set(drivername="postgresql").render_as_string(hide_password=False)
    with psycopg.connect(connection, sslmode="verify-full", sslrootcert=ca) as db:
        tables = db.execute("SELECT count(*) FROM pg_tables WHERE schemaname='public'").fetchone()[0]
        if tables:
            if db.execute("SELECT to_regclass('public.alembic_version')").fetchone()[0] is None:
                raise ValueError("Refusing a nonempty, unrelated database")
            if db.execute("SELECT version_num FROM alembic_version").fetchone() != ("0003",):
                raise ValueError("Existing databases require the documented backup/migration procedure")
    os.environ.update(DATABASE_URL=owner.set(drivername="postgresql+psycopg").render_as_string(hide_password=False),
                      FLEX_ENVIRONMENT=args.environment, DATABASE_CA_FILE=ca,
                      FIREBASE_PROJECT_ID=settings["FIREBASE_PROJECT_ID"])
    backend = Path(__file__).resolve().parents[1] / "backend"
    sys.path.insert(0, str(backend))
    os.chdir(backend)
    command.upgrade(Config("alembic.ini"), "head")
    with psycopg.connect(connection, sslmode="verify-full", sslrootcert=ca) as db:
        if db.execute("SELECT 1 FROM pg_roles WHERE rolname='flex_api'").fetchone():
            if not settings.get("RUNTIME_DATABASE_URL"):
                raise ValueError("Existing runtime role requires its recorded credential; no automatic rotation")
            runtime = make_url(settings["RUNTIME_DATABASE_URL"])
        else:
            password = secrets.token_urlsafe(32)
            db.execute(sql.SQL("CREATE ROLE flex_api LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT PASSWORD {}").format(sql.Literal(password)))
            labels = owner.host.split(".")
            labels[0] += "-pooler"
            runtime = owner.set(username="flex_api", password=password, host=".".join(labels), drivername="postgresql+psycopg")
        for statement in (
            "GRANT CONNECT ON DATABASE flex TO flex_api",
            "GRANT USAGE ON SCHEMA public TO flex_api",
            "GRANT SELECT, INSERT, UPDATE ON app_user, owned_record TO flex_api",
            "GRANT SELECT, INSERT ON linked_identity, account_registration, sync_receipt, audit_event TO flex_api",
            "GRANT SELECT ON role_assignment TO flex_api",
            "GRANT SELECT, INSERT, UPDATE, DELETE ON catalog_food TO flex_api",
        ):
            db.execute(statement)
        settings["RUNTIME_DATABASE_URL"] = runtime.render_as_string(hide_password=False)
        temporary = path.with_name(f".env.neon-write-{secrets.token_hex(8)}.json")
        temporary.write_text(json.dumps(settings, indent=2) + "\n")
        temporary.replace(path)
    with psycopg.connect(runtime.set(drivername="postgresql").render_as_string(hide_password=False),
                        sslmode="verify-full", sslrootcert=ca, prepare_threshold=None) as db:
        permissions = db.execute("SELECT current_user, has_schema_privilege(current_user,'public','CREATE'), "
                                 "has_table_privilege(current_user,'role_assignment','INSERT'), "
                                 "has_table_privilege(current_user,'owned_record','SELECT'), "
                                 "has_table_privilege(current_user,'audit_event','DELETE')").fetchone()
        if permissions != ("flex_api", False, False, True, False):
            raise ValueError("Unexpected runtime permissions")
    print(f"Verified {args.environment}: Alembic 0003, pooled TLS and restricted runtime permissions.")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        # Database exceptions can contain connection information or DDL; do not echo them.
        print(f"Provisioning failed: {type(exc).__name__}. Inspect state without printing credentials.", file=sys.stderr)
        raise SystemExit(1) from None
