# FLEX UI/UX architecture

## Audit and execution plan — 20 November 2026

Preserve Flutter, Riverpod 3, Navigator routes, SQLite migrations, integer nutrient snapshots, account-scoped outbox/inbox, Auth0 AppAuth and FastAPI ownership checks. Add product UI around these services; do not replace them.

1. Audit repository, historical documentation and available reference evidence.
2. Introduce the requested violet/teal/amber tokens, bundled Inter font and adaptive shell.
3. Extend local persistence for preferences, profile, notes, favorites and saved meals without modifying existing tables or cloud payload contracts.
4. Integrate dashboard, diary conveniences, search collections/custom foods, analytics, onboarding and settings.
5. Update the editable Figma file, verify layouts, run regressions and browser persistence checks.
6. Publish only the compiled guest browser app to the authorized RED Vercel team. Keep real account sync gated by existing acceptance requirements.

## Existing boundaries

- `mobile/lib/app.dart`: Riverpod diary/catalog/goals providers and diary routes.
- `mobile/lib/features/tracking.dart`: goals, weight, water, exercise and progress; reuse its editors and store.
- `mobile/lib/core/diary_store.dart`: audited SQLite v7, now additively upgraded to v8 for local product collections. Catalog, snapshots, drafts, guest filename and Android application ID remain stable.
- `account_session.dart`, `account_ui.dart`: configured native OIDC and secure credentials. Browser identity is explicitly unavailable.
- `backend/app`: owner-scoped API, JWT verification, durable receipts, export and readiness; SQLite on mobile remains immediately authoritative.

Local product preferences and convenience collections must be described as device-local. They are not silently added to the cloud sync contract. New schema work is additive and tested against populated older databases.

## Reference evidence

The user reconfirmed `C:\Users\shaba\Desktop\MyFitnessPal-Reverse`; that directory remains absent in this session. Focused searches of FLEX and the available Documents roots found no matching REA reports. REA device discovery returned `capability_unavailable`: its Windows ADB path is not configured. The Android SDK's explicit ADB executable was subsequently used only for the isolated FLEX build verification. No MyFitnessPal APK analysis or proprietary asset extraction was performed. The requested workflow categories guide original FLEX designs; no comparison with an observed current MyFitnessPal screen is claimed.

Historical documentation includes superseded design-only statements; current owning source and the latest phase evidence take precedence. Source inspection confirms existing tracker CRUD, dated goals, snapshot-safe diary writes, guest transfer and account isolation.
