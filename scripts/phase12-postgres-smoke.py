"""Run migrations and cloud API integration in a new local PostgreSQL cluster."""

import argparse
import os
from pathlib import Path
import secrets
import socket
import subprocess
import sys
import tempfile

import psycopg
from psycopg import sql


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bin", type=Path, help="PostgreSQL binaries directory")
    pg = parser.parse_args().bin.resolve()
    suffix = ".exe" if os.name == "nt" else ""
    root = Path(__file__).resolve().parents[1]
    backend = root / "backend"

    with tempfile.TemporaryDirectory(prefix=".pg-smoke-", dir=root) as temp:
        work = Path(temp)
        data = work / "data"
        passwords = secrets.token_hex(24), secrets.token_hex(24)
        admin_password, api_password = passwords
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            port = sock.getsockname()[1]

        def run(label, args, env=None):
            print(label, flush=True)
            # A Windows postgres child can inherit pipes from pg_ctl.
            log = work / "command.log"
            with log.open("wb") as output:
                result = subprocess.run(args, cwd=backend, env=env, stdout=output,
                                        stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL, timeout=220 if os.environ.get("FLEX_RUN_FLUTTER_SYNC") else 75)
            message = log.read_text(errors="replace")
            for password in passwords:
                message = message.replace(password, "[redacted]")
            print(message, end="", flush=True)
            if result.returncode:
                raise SystemExit(result.returncode)

        pwfile = work / "initdb-auth.txt"
        pwfile.write_bytes(admin_password.encode("ascii") + b"\n")
        run("Initializing UTF-8 cluster", [
            pg / ("initdb" + suffix), "-D", data, "-U", "flex_admin", "-A", "scram-sha-256",
            "-E", "UTF8", "--pwfile", pwfile,
        ])
        pwfile.unlink()

        options = dict(host="127.0.0.1", port=port, user="flex_admin",
                       password=admin_password, connect_timeout=5, autocommit=True)
        ctl = [pg / ("pg_ctl" + suffix), "-D", data]
        try:
            run("Starting localhost cluster", ctl + [
                "-l", work / "postgres.log", "-o", f"-h 127.0.0.1 -p {port}", "-w", "-t", "20", "start",
            ])
            with psycopg.connect(**options, dbname="postgres") as conn:
                print("PostgreSQL", conn.execute("SHOW server_version").fetchone()[0], flush=True)
                conn.execute("CREATE DATABASE flex_tests")
                conn.execute("REVOKE CONNECT ON DATABASE flex_tests FROM PUBLIC")
                conn.execute(sql.SQL("CREATE ROLE flex_api LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD {}")
                             .format(sql.Literal(api_password)))
                conn.execute("GRANT CONNECT ON DATABASE flex_tests TO flex_api")

            endpoint = f"127.0.0.1:{port}/flex_tests"
            env = dict(os.environ, DATABASE_URL=f"postgresql+psycopg://flex_admin:{admin_password}@{endpoint}")
            def migrate(*args):
                run("Alembic " + " ".join(args), [sys.executable, "-m", "alembic", *args], env)

            migrate("upgrade", "0001")
            with psycopg.connect(**options, dbname="flex_tests") as conn:
                conn.execute("INSERT INTO app_user (id, identity_subject) VALUES ('legacy', 'legacy')")
            migrate("upgrade", "0002")
            migrate("downgrade", "0001")
            with psycopg.connect(**options, dbname="flex_tests") as conn:
                assert conn.execute("SELECT identity_subject FROM app_user WHERE id='legacy'").fetchone() == ("legacy",)
            migrate("upgrade", "head")
            migrate("current")
            with psycopg.connect(**options, dbname="flex_tests") as conn:
                assert conn.execute("SELECT identity_issuer, active FROM app_user WHERE id='legacy'").fetchone() == ("", True)
                conn.execute("GRANT USAGE ON SCHEMA public TO flex_api")
                conn.execute("GRANT SELECT, INSERT, UPDATE, DELETE ON app_user, owned_record, sync_receipt, linked_identity, account_registration TO flex_api")
                assert not conn.execute("SELECT has_schema_privilege('flex_api', 'public', 'CREATE')").fetchone()[0]

            run("Signed identity and ownership tests using PostgreSQL", [sys.executable, "-m", "pytest", "-q", "tests/test_cloud.py"],
                dict(os.environ, FLEX_TEST_POSTGRES_URL=f"postgresql+psycopg://flex_api:{api_password}@{endpoint}"))
            archive = work / "flex.dump"
            pg_env = dict(os.environ, PGPASSWORD=admin_password)
            pg_args = ["-h", "127.0.0.1", "-p", str(port), "-U", "flex_admin"]
            run("Backing up isolated database", [pg / ("pg_dump" + suffix), *pg_args,
                "--format=custom", "--file", archive, "flex_tests"], pg_env)
            with psycopg.connect(**options, dbname="postgres") as conn:
                conn.execute("CREATE DATABASE flex_restore")
            run("Restoring into a separate database", [pg / ("pg_restore" + suffix), *pg_args,
                "--exit-on-error", "--no-owner", "--no-acl", "-d", "flex_restore", archive], pg_env)
            with psycopg.connect(**options, dbname="flex_tests") as source, psycopg.connect(
                    **options, dbname="flex_restore") as restored:
                for table in ("alembic_version", "app_user", "owned_record", "sync_receipt", "linked_identity", "account_registration", "role_assignment", "catalog_food", "audit_event"):
                    query = sql.SQL("SELECT to_jsonb(t) FROM {} t ORDER BY to_jsonb(t)").format(sql.Identifier(table))
                    rows = source.execute(query).fetchall()
                    if table in ("alembic_version", "app_user", "owned_record", "sync_receipt", "linked_identity", "account_registration"):
                        assert rows, f"Expected fixture rows in {table}"
                    assert rows == restored.execute(query).fetchall(), f"Restore differs in {table}"
                    print(f"Restore verified {len(rows)} rows in {table}", flush=True)
            # Revision 0003 requires backup restoration instead of discarding linked identities.
        finally:
            if (data / "postmaster.pid").exists():
                run("Stopping isolated cluster", ctl + ["-w", "-t", "20", "-m", "fast", "stop"])


if __name__ == "__main__":
    main()
