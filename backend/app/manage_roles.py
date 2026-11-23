"""Trusted operator command; never exposed as an HTTP endpoint."""
import argparse
from types import SimpleNamespace
from uuid import UUID

from sqlalchemy.orm import Session

from .admin import audit
from .config import Settings, make_engine
from .models import RoleAssignment, User


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("account_id", type=UUID)
    parser.add_argument("role", choices=["user", "support", "admin", "super_admin"])
    parser.add_argument("--reason", required=True)
    args = parser.parse_args()
    if not 8 <= len(args.reason.strip()) <= 240:
        parser.error("Reason must contain 8–240 characters")
    engine = make_engine(Settings())
    if engine is None:
        parser.error("DATABASE_URL is required")
    try:
        with Session(engine) as db, db.begin():
            user = db.get(User, str(args.account_id), with_for_update=True)
            if user is None or not user.active:
                parser.error("An active account must already exist")
            assignment = db.get(RoleAssignment, user.id)
            if args.role == "user":
                if assignment:
                    db.delete(assignment)
            elif assignment:
                assignment.role = args.role
            else:
                db.add(RoleAssignment(owner_id=user.id, role=args.role))
            # The database operator is authenticated outside this application.
            audit(db, SimpleNamespace(id="trusted-database-operator"),
                  "role_assigned", user.id, f"{args.role}: {args.reason.strip()}"[:240])
    finally:
        engine.dispose()


if __name__ == "__main__":
    main()
