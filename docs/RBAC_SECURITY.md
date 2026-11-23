# RBAC and security boundaries

| Role | Permissions |
|---|---|
| User | Own consumer records, explicit credential linking; no admin APIs |
| Support | Aggregate overview, minimal UUID directory and catalog read |
| Admin | Support permissions; administrative audit read, consumer suspension and managed-catalog writes |
| Super Admin | Admin permissions; reserved authority for future privileged configuration |

Roles live in `role_assignment`, not client input, Google identity attributes, phone numbers or email domains. No initial administrator is seeded. Trusted database operators may run `python -m app.manage_roles ACCOUNT_UUID ROLE --reason "approved access ticket"`. The command requires an existing active account and records an audit event. No HTTP privilege-assignment endpoint exists.

Every admin API uses the shared authenticated/active owner dependency and checks staff membership. Mutations require Admin/Super Admin plus authentication within five minutes. Staff accounts and the acting administrator cannot be suspended through the consumer-status endpoint. Catalog updates/deletion use explicit revisions to reject stale changes.

Directory responses exclude names, email, phone, raw provider subjects, diary payloads and personal tracker values. Support cannot read audit reasons. Audit records contain actor/target UUID, bounded purpose, action and timestamp; no access/refresh tokens. Operators must avoid entering personal or secret data in free-text reasons.

The backend now enforces a 256 KiB body limit and a bounded per-process fixed-window limit of 240 requests/minute per verified identity. Use one worker as configured; shared throttling is required before horizontal scaling. Neon runtime roles can insert/read audit events but cannot update/delete them, assign staff roles or create schema objects. Owner credentials are separate and never enter frontend builds or the deployment source repository.

Production gates: provider revocation strategy, trusted-role operational review, deployed CORS allowlist and end-to-end role testing. Aggregate activity is not analytics-event collection. No Firestore/Storage database is introduced; do not open rules for unrelated Firebase services.
