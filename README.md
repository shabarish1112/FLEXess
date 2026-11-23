# FLEX

Independent local-first Android and browser nutrition diary development build. The bundled catalog uses USDA Foundation Foods and preserves source attribution. See docs/FOOD_CATALOG.md.

Team: [Your member instructions](../README.md) — Shabarish (host/maintainer), Pramod (backend/database), Harshita (consumer UI/UX), Prajwal (admin/data/sync/QA). This extracted workspace contains the complete project source. Your assigned editing scope and upload instructions are in the outer member README.

UI/UX: [Design system](docs/DESIGN_SYSTEM.md) · [Feature completeness](docs/FEATURE_COMPLETENESS.md) · [Audit](docs/UI_UX_AUDIT.md) · [Figma](https://www.figma.com/design/leE6qFHI8f29Y5LKxJSrak).

FLEX 2: [Live app](https://flex-fitness-98e76.web.app) · [Live administration](https://flex-fitness-98e76-admin.web.app) · [API readiness](https://flex-nutrition-api.onrender.com/health/ready). Google login and the explicitly approved owner Admin account are verified. Existing consumer data and SQLite v8 are preserved. The separate admin entrypoint is `mobile/lib/admin_main.dart`.

[Deployment and environment commands](docs/FIREBASE_DEPLOYMENT.md) · [Admin architecture](docs/ADMIN_PLATFORM_ARCHITECTURE.md) · [Authentication](docs/AUTHENTICATION_INTEGRATION.md) · [RBAC](docs/RBAC_SECURITY.md) · [Verification](docs/TEST_REPORT.md) · [Readiness and remaining work](docs/PRODUCTION_READINESS.md). Free hosting has cold starts and quota suspension; publication does not establish complete production readiness.

## Browser

From `mobile`:

```powershell
flutter pub get
dart run sqflite_common_ffi_web:setup
flutter run -d chrome --web-port=8766
flutter build web --release --no-web-resources-cdn
```

These commands create a guest build. Configured consumer/admin builds use separate development and production Firebase projects and observed Render API URLs; follow [deployment instructions](docs/FIREBASE_DEPLOYMENT.md). The browser stores guest records in IndexedDB for that site. Clearing site data removes them; different origins and Android have separate local records. The earlier Vercel release remains guest-only and unchanged. Live cross-device sync/linking acceptance is outstanding. Offline page reload is unavailable. No backend or credentials are required for guest logging. SQLite worker/WASM files are checked in; rerun setup if their package version changes.

## Mobile

Run from mobile:

```powershell
flutter pub get
flutter analyze
flutter test
flutter run -d emulator-5554
```

Open Diary, select a meal, choose a sample food, change serving or quantity, and Add to diary. Tap a logged row to edit it. Open Nutrition for meal and daily summaries. The app stores entries on device and has no server dependency.

## Backend foundation

From backend, create a venv, install requirements.txt, set DATABASE_URL, then run:

```powershell
python -m alembic upgrade head
python -m uvicorn app.main:app
python -m pytest -q
```

The backend exposes /health/live and /health/ready. The contract under contracts/ is the proposed product API. The mobile app runs fully offline.


Phase 9 notes: [Brand](docs/BRAND.md) · [Catalog import](docs/FOOD_CATALOG.md) · [Verification](docs/TEST_RESULTS.md). Drafts resume from Diary and remain separate from totals until Add succeeds.
