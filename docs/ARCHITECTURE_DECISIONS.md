# Architecture decisions

- Flutter Material 3 and feature domain types. Riverpod provides asynchronous state, repository injection and test overrides with little boilerplate. Bloc's explicit events are an alternative when the workflow grows.
- sqflite provides versioned SQLite, transactions and FFI tests without Drift code generation. V1 stores entry metadata and nullable integer nutrient snapshots together. This avoids partial commits. Integer milliscale quantities and known/missing summaries preserve the independent nutrition rules.
- The selected day is a local calendar key. A release-ready catalog migration needs versioned serving definitions and durable reference snapshots before catalog replacement.
- FastAPI and SQLAlchemy/Alembic form a modular foundation. PostgreSQL is the intended server database. The managed identity boundary will verify issuer, audience, expiry and signature, map the subject to app_user, then scope all user operations by that user. Protected product endpoints are pending that implementation.
- Sources: https://docs.flutter.dev/app-architecture/design-patterns/offline-first, https://pub.dev/packages/flutter_riverpod, https://pub.dev/packages/sqflite, https://fastapi.tiangolo.com/tutorial/body/

Phase 9 adds v2 tables alongside v1 entries and preferences, backfills known fixture food snapshots, and preserves the existing Android app ID and database filename. Committing inserts the entry and removes the draft in the same transaction. Search is local, parameterized and bounded to 100 rows, with exact and prefix matches ahead of substring matches. Export import normalizes only the nutrients supported by this development build.

## Phase 10

V3 adds date-effective targets and local tracking rows with canonical grams, milliliters and minutes. Duplicate weight dates are allowed; the latest recorded row supplies the trend point and exercise estimation base. Nutrition targets remain explicit; legacy energy is fallback before a dated setting. Remaining energy adds one daily sum of estimated exercise only when enabled. The estimate uses rough presets (3/5/8 MET) and subtracts one resting MET before applying 3.5 × kg × minutes / 200. It is an approximation; missing weight or unspecified intensity yields unknown. Source for MET convention: https://pmc.ncbi.nlm.nih.gov/articles/PMC10818145/.

The tracking affordance is in the FLEX app bar, with a Progress route inside Tracking. It keeps the three primary diary destinations. Progress uses up to 90 local days and displays weight chart values with text equivalents, food totals with missingness, water and exercise history.

## Phase 11

Use the Phase 11 authentication and synchronization design documents as the proposed implementation boundaries. Preserve account-scoped queues and explicit consent for guest data. The current backend health-only runtime and guest-local mobile database are unchanged.
