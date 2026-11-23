# FLEX 2 production readiness

Status: deployed on the approved free architecture, with remaining production-readiness limitations. The earlier Vercel consumer release is unchanged. Exact environments and URLs are in `deployment-status.json`.

Implemented: separate Flutter consumer/admin entrypoints, Google and guarded fictional-phone interfaces, exact-project Firebase JWT verification alongside Auth0, ownership-preserving linking, additive identity migration, database-authoritative staff roles, minimal directory, audited account suspension and roles, revisioned catalog CRUD/import, real aggregate reports, responsive themes and reduced-motion interactions.

Verified live: both APIs pass HTTPS liveness/database readiness; anonymous admin requests are rejected; untrusted production CORS is rejected; development consumer/admin origins are allowed. Both environments have separate Spark consumer/admin deployments and restricted Neon credentials. Development Google login, nonstaff denial and approved Admin overview/users/audit access passed. Production Google login, approved Admin overview and session restoration after reload also passed.

Remaining work and material limits:

- Admin was assigned only to the explicitly approved owner account in each environment, through the audited operator CLI. Production Admin overview and restored-session browser acceptance passed. Test each additional staff role and sensitive write workflow before operational use.
- Signature verification does not query Firebase revocation or disabled-user state. Backend suspension is checked on every request; externally revoked ID tokens can remain valid until expiry. Staff operations require recent authentication where applicable. Establish the provider revocation process before a security-sensitive launch.
- Rate limiting is process-local for the single-worker Free deployment. Immutable audit retention, alerting, operational telemetry, recovery drills and production workload acceptance remain outstanding.
- Free hosting cannot guarantee continuous availability. Render services sleep and share workspace quotas; Neon suspends idle compute. No keep-alive or paid fallback is configured.
- Account erasure, advanced mobile chart/milestone interactions and full operations analytics are incomplete. Uninstrumented metrics are explicitly unavailable.
- Fictional phone-number configuration/live OTP acceptance, native Android Google login, cross-device sync/linking and restored-session acceptance are not yet verified. No real SMS is authorized.
- Production Android's Firebase package registration and release signing are incomplete. Configured development APK build/runtime results are tracked separately in `TEST_REPORT.md`.

Only new, initially empty cloud databases were migrated. Existing local diary records and legacy identifiers were preserved. No destructive production migration was performed. Successful publication is not proof that the entire FLEX 2 brief is complete.


