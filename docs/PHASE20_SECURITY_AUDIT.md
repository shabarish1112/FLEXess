# Phase 20 security audit

- High, open. Real Auth0 login, Android HTTPS sync and managed PostgreSQL identity/TLS require live acceptance. Keep ordinary account sync disabled.
- High, open. Account erasure needs a verified fresh-auth flow, session revocation, protection against account recreation, pending client operation handling and backup retention policy.
- Medium, mitigated in code. Validation errors no longer echo submitted fields. Request metadata logs carry generated request IDs and status codes. The container disables raw access logs. Read and write API responses use no-store.
- Medium, mitigated in code. Staging requires PostgreSQL with a trusted CA and hostname verification, explicit CORS origins, full managed identity settings and bounded pools. Runtime PostgreSQL DDL denial was verified in the smoke cluster.
- Medium, open. Run dependency and secret scans from CI before release. Production retention and account deletion require policy review.

The account export returns only the authenticated owner's records and tombstones. A bounded UUID cursor is supported. Export scope covers current server records, excluding local guest data.
