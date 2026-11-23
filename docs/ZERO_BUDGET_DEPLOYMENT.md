# Strict ₹0 deployment configuration

User-approved architecture: Firebase Hosting Spark; Render Free Python web services; Neon Free PostgreSQL; Firebase Google sign-in. No card registration, Blaze, Cloud Run, Cloud SQL, paid services, automatic upgrades, paid SMS or quota-bypassing keep-alive jobs.

## Limits verified from official sources — 2026-11-20

| Service | Free constraints and budget response |
|---|---|
| Firebase Hosting Spark | 10 GB hosting storage and 10 GB/month transfer. Quota exhaustion blocks deployment or disables serving until reset; do not upgrade. |
| Firebase Auth | Google/social sign-in is a no-cost feature. Real verification SMS is Blaze-only. Use fictional test numbers only in development; no real SMS enablement. |
| Render Free | 750 running instance-hours per workspace/month, shared by dev/prod; sleep after 15 minutes idle and approximately one-minute cold starts. Bandwidth/build overages suspend services/builds without a payment method. No persistent disk, SSH or one-off jobs. Workspace billing UI verified Hobby, no card, no pending charges, 5 GB bandwidth and 500 pipeline minutes; these quotas are shared across services. |
| Neon Free | No card required; 100 CU-hours and 1 GB PostgreSQL storage per project, 5 GB/month transfer. Compute suspends at allowance exhaustion; storage-increasing writes fail at capacity. Separate projects isolate development and production. |

Sources: [Firebase Hosting](https://firebase.google.com/docs/hosting/usage-quotas-pricing), [Firebase plans](https://firebase.google.com/docs/projects/billing/firebase-pricing-plans), [Firebase Auth limits](https://firebase.google.com/docs/auth/limits), [fictional phone numbers](https://firebase.google.com/docs/auth/android/phone-auth#test-with-fictional-phone-numbers), [Render Free](https://render.com/docs/free), [Neon Free](https://neon.com/pricing).

This budget supports an intermittent demonstration with service suspension/cold starts. It cannot guarantee uninterrupted production availability. Render warns against production use of its free instances. Never evade limits using synthetic traffic or silently switch to a paid tier.

## Repository configuration

`render.yaml` defines two explicitly `plan: free` services, one worker each, automatic deploys off, separate Firebase issuers and externally supplied database URLs/CORS allowlists. No Render databases, disks or paid pre-deploy jobs are created. `backend/.python-version` pins the supported Python runtime.

Render health checks use `/health/live` so infrastructure probes do not continually wake Neon. Validate `/health/ready` separately during deployment acceptance. Small connection pools (2, no overflow), verified TLS and the OS CA bundle protect Neon connections. Neon credentials belong only in backend secrets. Use a migration-owner connection for Alembic, a least-privilege runtime role for the API and no migrations on every application boot.

Firebase Hosting serves static consumer/admin builds only. It does not host FastAPI. A dedicated admin site avoids overwriting the existing consumer site. CORS uses only the exact observed Hosting origins; never a wildcard. Frontend build configuration contains public Firebase options and the actual Render HTTPS API origin, never PostgreSQL credentials.

Phone controls reject all real-number SDK requests. Only development builds with `FLEX_FIREBASE_PHONE_TESTS=true` and an explicit configured test-number allowlist can call phone verification. No test OTP is embedded in the client; reCAPTCHA/app verification stays enabled. Production builds remain Google-only. Test accounts never receive staff roles automatically.

## Provisioning order and current gates

1. Verify account plans/payment state; stop if any provider requires payment information.
2. Create approved development Firebase project/apps on Spark; enable Google, authorized domains and only the agreed test-number configuration. Production billing stays unchanged.
3. Connect Neon and Render accounts. Create separate Neon Free projects and restricted runtime roles. Apply Alembic 0003 to their initially empty databases; verify readiness without touching local diary records.
4. Create Render Free dev service from the reviewed repository revision. Set server-only secrets, verified CA path and exact development CORS origins. Record its actual returned HTTPS URL.
5. Build and publish the development Hosting sites with that URL. Test Google login, restored sessions, anonymous/nonstaff rejection, trusted operator role assignment and authorized admin/catalog workflows.
6. Complete remaining production gates before publishing production resources. Record actual URLs only after deployment reports success and HTTP checks pass.

Current verified resource state is recorded in `deployment-status.json`. Both Neon Free databases are provisioned at Alembic 0003 with restricted `flex_api` roles and verified pooled TLS. Development Firebase exists on Spark with Google enabled and Android fingerprints registered. The private deployment mirror is pushed at revision `003455c`.

Both Render Free APIs passed HTTPS/database readiness. Development consumer: `https://flex-fitness-dev-98e76.web.app`; development admin: `https://flex-fitness-dev-98e76-admin.web.app`. Live consumer Google login succeeded. Production consumer/admin frontends are also published, and approved owner Admin access passed in both environments. See `deployment-status.json` for exact API URLs.

The runtime rejects bodies above 256 KiB and limits each verified identity to 240 requests per fixed minute. The limiter is process-local and bounded to 10,000 identity entries; the blueprint uses one worker and a concurrency limit of 32. These safeguards reduce abuse but do not guarantee availability on free tiers.

For an explicitly new, empty Neon database, `scripts/provision-neon.py` applies the canonical Alembic migrations and creates/verifies the runtime role. It refuses unrelated or older nonempty schemas. Input is an ignored `.env.neon-*.local.json` server configuration, not a frontend build file. Never copy these credentials to Flutter or GitHub.




