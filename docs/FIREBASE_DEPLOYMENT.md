# FLEX Firebase and Render deployment

Verified on 2026-11-21. Both Firebase projects use Spark. Render uses Hobby with no card on file and two Free services. Neon uses Free with separate development/production databases. No billing upgrade or real SMS request was made.

| Environment | Consumer | Administration | FastAPI |
| --- | --- | --- | --- |
| Development | https://flex-fitness-dev-98e76.web.app | https://flex-fitness-dev-98e76-admin.web.app | https://flex-nutrition-api-dev.onrender.com |
| Production | https://flex-fitness-98e76.web.app | https://flex-fitness-98e76-admin.web.app | https://flex-nutrition-api.onrender.com |

Both APIs passed HTTPS `/health/live` and `/health/ready` checks, including Neon connectivity. Anonymous administrator access returns 401. Development Google login, consumer denial and user-approved Admin access to real overview/user/audit data passed. Production authentication acceptance is recorded in `deployment-status.json` as checks finish. Publication does not establish complete production readiness; see `PRODUCTION_READINESS.md`.

`.firebaserc` maps `consumer` and `admin` separately for each project. `firebase.json` uses development artifacts; `firebase.production.json` uses distinct production artifacts. Both provide SPA rewrites and security headers. Never deploy a development build with the production project flag. The previous Vercel release remains unchanged.

Public Firebase options and observed API URLs are in ignored platform-specific `mobile/config/*.local.json` files. PostgreSQL runtime credentials exist only in ignored server configuration and Render environment variables. Owner credentials remain local. Do not copy server credentials to Flutter, GitHub or this document.

Build sequentially from `mobile` (web and Android share generated assets):

```powershell
flutter build web --release --no-web-resources-cdn --dart-define-from-file=config/development.web.local.json --output=build/consumer
flutter build web --release --no-web-resources-cdn --dart-define-from-file=config/development.web.local.json --target=lib/admin_main.dart --output=build/admin
flutter build web --release --no-web-resources-cdn --dart-define-from-file=config/production.web.local.json --output=build/production-consumer
flutter build web --release --no-web-resources-cdn --dart-define-from-file=config/production.web.local.json --target=lib/admin_main.dart --output=build/production-admin
```

Deploy from the repository root after verifying the intended build/environment:

```powershell
firebase deploy --project flex-fitness-dev-98e76 --only hosting --config firebase.json
firebase deploy --project flex-fitness-98e76 --only hosting --config firebase.production.json
```

The latest CLI used here was firebase-tools 15.37.0. Hosting rollback uses the console's previous release; Firebase project data and authentication are not part of a Hosting rollback.

Render source: private `shabarish1112/FLEX-Nutrition-API`, branch `codex/flex-2-free-deploy`, commit `003455c`. Both services use Python 3.14.8, root `backend`, the runtime lockfile, one worker, `/health/live`, verified database TLS, small pools and explicit Hosting CORS origins. Automatic deploys are off. Apply additive migrations through the trusted database operator before manually deploying API changes. Do not downgrade migration 0003 or remove identity links as an automated rollback.

Development Android is registered as `dev.independent.fitness_diary.isolatedtest` with the debug SHA-1/SHA-256 fingerprints. The existing production Firebase Android registration uses `com.example.flex`, which does not match the application's base package `dev.independent.fitness_diary`. A production Android registration and release signing remain outstanding; never reuse the mismatched registration.

Google is enabled in both projects. The exact admin `.web.app` domains were authorized after user confirmation. Existing production email/phone provider settings were preserved. The app rejects production phone verification and permits development fictional numbers only when explicitly configured; no fictional number has yet been configured for live acceptance.

Free tiers impose cold starts and suspension at quotas. See `ZERO_BUDGET_DEPLOYMENT.md` for verified limits. Do not add keep-alive traffic, paid plans, a card, Blaze, Cloud Run or Cloud SQL.

Configured development APKs are preserved under `mobile/build/releases`: `FLEX-2.0.1-dev-x86_64-isolated-debug.apk` for the emulator and `FLEX-2.0.2-dev-arm64-isolated-debug.apk` for ARM64 phones. Both use the live development backend, not production records. Native installation/login acceptance is pending; hashes and package facts are in `TEST_REPORT.md`.
