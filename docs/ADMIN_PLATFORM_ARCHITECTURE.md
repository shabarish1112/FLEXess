# FLEX Admin architecture and inventory

## Existing inventory

Flutter/Riverpod consumer application; SQLite v8 local records; durable sync queues and guest transfer; native Auth0/AppAuth; FastAPI, SQLAlchemy, Alembic and PostgreSQL cloud store. The previous Vercel URL serves a consumer build. There was no admin shell, Firebase client configuration, staff model, managed server catalog or operational audit table before this phase.

## Decision

Use the existing Flutter toolchain with a separate `lib/admin_main.dart` entrypoint. Administration does not initialize or read consumer SQLite. It shares theme tokens, Firebase sign-in controls and the HTTPS API client, with a desktop rail/drawer, command area, breadcrumbs, responsive tables and operational routes. A React/Next rewrite would add a second component ecosystem, dependency pipeline and identity client without a demonstrated requirement.

## Implemented routes

| Route | Data and actions |
|---|---|
| /overview | Actual account counts, measured registrations, catalog count, current-record update counts and metric definitions; 7/30/90 day ranges |
| /users | UUID search, 25-row pagination, status/role/date/issuer inspection; audited enable/suspend for consumer accounts |
| /catalog | Food search, bounded nutritional fields, serving grams, category, verified/draft status, duplicate-name warning, revision-checked edits/deletion, bounded atomic JSON import |
| /analytics | Registration growth and current-record activity with precise measurement limits; JSON report-page export |
| /operations | Protected administrative audit events; uninstrumented operational metrics explicitly unavailable |
| /settings | Current server-authorized identity/role, reauthentication and trusted-role assignment policy |

Every route is behind `/v1/admin/me` and every backend endpoint independently checks database staff assignments. Reports copy the current page as JSON; this is not an all-pages export. No arbitrary SQL or server secrets enter the client.

Verified managed foods are available to signed-in consumers through `/v1/catalog` and the Online catalog search collection. Existing food snapshots and bundled USDA catalog remain intact.

Global search (Ctrl+K) queries managed foods and UUID-shaped account queries, with role-appropriate inspection. The activity icon opens the real audit history; it does not invent an unread-notification count.

Outstanding: a notifications service, provider-method (Google versus phone) analytics, retention/platform/event instrumentation, API latency/error history, failed-sync/job telemetry, staff configuration editing and full operational alerting. These need real contracts and measurements, not mock controls.
