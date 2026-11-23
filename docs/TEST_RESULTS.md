# Test results

- Flutter stable 3.47.0 and Dart 3.13.0. Dependencies resolved.
- dart format lib test completed. flutter analyze found no issues after lint fixes.
- flutter test: 3 passed. Covered portion and quantity scaling, missing values, invalid inputs, date rollover, duplicate SQLite key rejection, close/reopen persistence, separate dates, multi-meal totals, update/delete, and widget navigation from search to preview and committed diary.
- python -m pytest -q: 2 passed. Backend liveness and database readiness verified. Starlette emitted an httpx deprecation warning.
- Alembic upgrade head passed against SQLite and created app_user. PostgreSQL was not exercised.
- First flutter build apk --debug failed reading the shared Gradle daemon registry. The isolated cache retry and emulator journey are tracked separately.
The widget flow also passed a failed-write injection: the preview stayed open with its value and error, then committed on retry.

## Android emulator

- x86_64 APK assembled successfully with Gradle 9.3.1, Android Studio JBR 25, a project-local Gradle user home, and the existing read-only dependency cache. Artifact: mobile/build/app/outputs/apk/debug/app-debug.apk.
- ADB installed the APK on emulator-5554 and launched dev.independent.fitness_diary. The first UIAutomator pass reached startup too early. A subsequent pass created the synthetic oats entry with 152 kcal; an exact-label selector then missed the merged row semantics. The saved hierarchy confirmed the entry existed.
- Resumed against that record. Changed quantity to 2, saved, and verified 304 kcal. Force-stopped and relaunched the package, reopened Diary, and verified the entry and 304 kcal. Deleted only that entry and verified it was absent and energy returned to zero. See docs/android-*.xml.
- Android builds for physical ARM devices and release signing remain unverified.

## Phase 9

- Baseline flutter test --no-pub: 3 passed. Backend python -m pytest -q: 2 passed.
- dart format and flutter analyze --no-pub: passed after correcting the MaterialApp light theme property.
- Flutter regression: 5 passed after allowing actual SQLite async queries to settle in the widget test. Verified v1 data/goal migration, draft restart and discard, atomic commit, duplicate rejection, catalog replacement and old snapshots, invalid input, and retry on a failed diary write.
- Python USDA normalization test: 1 passed. OpenAPI 3.1 validator: contracts/design.openapi.yaml OK.
- Gradle 9.3.1 assembleDebug for Android x86_64: passed. PostgreSQL test-cluster attempts stopped at initdb because the child could not read the password file. No PostgreSQL readiness or migration result.
- aapt dump badging verified label FLEX and the original dev.independent.fitness_diary application ID.
- scripts/phase9-draft-smoke.ps1 passed on emulator-5554. In-place adb install -r, launch, save draft without committed entry, force-stop/relaunch, resume, exactly one committed entry, and deletion of only that synthetic record all completed. Existing nonempty v1 entry and goal preservation were verified in the separate SQLite migration test.

## Phase 10

Flutter analyzer clean and ten tests passed, including USDA offline search and populated v2 migration. The importer unit test and OpenAPI validation passed. Both backend tests passed. A disposable PostgreSQL 18.4 cluster passed upgrade, readiness and downgrade. The Android x86_64 debug APK built.

The Phase 10 x86_64 debug APK installed in place and MainActivity launched. Confirm the USDA search, serving preview, journal commit and cleanup with the emulator smoke before release.
The UI smoke exited with ADB failed: shell after installation and launch. No end-to-end diary result was confirmed.

## Phase 11

PowerShell 7 smoke validation: standalone ADB shell, boot, activity and hierarchy checks passed with Windows ADB access. Flutter formatting, analysis and all 10 tests passed. With PYTHONPATH set to backend/.deps, two backend tests and OpenAPI validation passed. One Python USDA importer test passed.
The recovered API 37 emulator passed real USDA search, provenance, 194 kcal for two reference servings, and discard of the temporary draft.
The guarded device journey saved one Breakfast banana row, and separate uncompressed capture verified restart persistence and cleanup. PowerShell syntax was checked. A fresh debug build was not completed: the Gradle wrapper was downloading its distribution when cancelled.
The Phase 11 disposable PostgreSQL rerun was stopped without a migration result. The previous Phase 10 upgrade, readiness and downgrade result remains the verified PostgreSQL baseline.

## Phase 12

- Ten backend tests passed in the default suite with one PostgreSQL-only skip. The isolated PostgreSQL 18.4 run passed all nine cloud tests and the Alembic upgrade, downgrade and re-upgrade. Alembic SQLite upgrade and downgrade also passed.
- Proposed and generated runtime OpenAPI validated. The USDA importer test passed.
- Standard x86_64 debug APK assembled offline with a workspace-local Gradle home. First isolated package attempt failed with a JVM native memory allocation error.
- Flutter formatting and analyzer passed. All 14 Flutter tests passed with one test worker. The migration and guest tests, rollback injection, durable outbox, retry, conflict and expired-authorization checks were included.
- The isolated APK did not build after a second one-worker retry. Dart and the JVM reported memory exhaustion. No Phase 12 package was installed on the existing emulator.

## Phase 13

Flutter analyzer clean and 15 tests passed, including inbox cursor restart, replay, tombstones and rollback.

## Phase 14

Dart formatting and Flutter analysis passed. All 16 Flutter tests passed. Backend pytest: 10 passed and 1 PostgreSQL-only skip. Isolated PostgreSQL 18.4: 9 passed, with Alembic upgrade, downgrade and re-upgrade. The proposed OpenAPI contract validated. No Phase 14 Android or authenticated two-client run.

## Phase 15

Flutter formatting and analysis passed. Default Flutter suite: 16 passed with one opt-in skip. Default backend suite: 10 passed with two opt-in skips. Opt-in PostgreSQL suite: 10 passed including the Flutter TLS journey. Alembic upgrade, rollback, and re-upgrade passed. Proposed OpenAPI validated.

## Phase 16

Flutter formatting and analyzer passed. 19 Flutter tests passed and one opt-in network test was skipped in the default run. The three new tests use provider and vault doubles.
Default backend: 10 passed, two opt-in skips. Isolated PostgreSQL 18.4: 10 passed, including the signed Flutter two-client TLS test. Alembic upgrade, downgrade and re-upgrade passed. Proposed OpenAPI validated. x86_64 Android debug APK built; device sign-in and live sync remain unverified.

## Phase 17

Flutter formatting and analysis passed after formatting the Phase 15 assertion. Flutter tests: 21 passed and one opt-in skip. Default backend: 10 passed and two opt-in skips. Proposed OpenAPI validated. Isolated x86_64 debug build and install passed; System UI ANR blocked the guest diary smoke before writes.
Isolated PostgreSQL 18.4: 10 passed including the Flutter TLS journey. Alembic upgrade, rollback and re-upgrade passed. The emulator System UI ANR remained after Wait and after host tests finished.

## Phase 18

Formatting and analysis passed. Flutter 21 passed plus one opt-in skip. Default backend 10 passed plus two opt-in skips. PostgreSQL 18.4 opt-in suite 10 passed, including the real loopback Flutter TLS harness with an explicit untrusted certificate rejection before trusted transport. Alembic upgrade, downgrade and re-upgrade passed. OpenAPI validated. Public configuration preflight unit tests: 3 passed. With local settings absent the live preflight failed closed and named the four missing public variables.

The isolated x86_64 debug APK built offline in 1m51s. AAPT confirmed the isolated package, disabled backup and AppAuth callback scheme. ADB and hierarchy capture worked independently. The guest smoke completed across guarded resumes and verified draft persistence, one committed entry surviving restart, a visible 194 to 291 kcal edit and cleanup back to 0 kcal.

## Phase 18B

Flutter formatting and analysis passed. 24 Flutter tests passed with one opt-in skip, including AppAuth channel parameters, cancelled hosted logout and the public-client fallback after restore. Default backend: 10 passed and two opt-in skips. Disposable PostgreSQL 18.4: 10 passed including the two-client signed TLS test. Alembic upgrade, downgrade and re-upgrade passed. OpenAPI validation and four preflight unit tests passed. The live preflight failed closed because all four public settings are absent.

Isolated x86_64 offline debug APK built in 1m45s. AAPT verified the AppAuth receiver and shared scheme. The isolated APK installed alongside the original FLEX package.
After the isolated launch transiently returned null accessibility roots, resuming without another restart passed guest USDA search, source attribution, the doubled serving preview and temporary draft discard.

## Phase 18C and Phase 19 Progress refresh

Auth0 preflight ran once and exited 1 for the four missing public settings. Four preflight unit tests passed. Flutter formatting and analysis passed. Final Flutter regression: 25 passed and one opt-in skip. The Progress widget verified a remote insert at 152 kcal, an edit to 304 kcal, an unchanged display after rollback and empty history after deletion. The first widget run caught a Future-returning setState callback, which was corrected before the passing full run. Default backend: 10 passed and two opt-in skips. Disposable PostgreSQL 18.4: 10 passed including the two-client TLS harness and untrusted certificate rejection. Alembic upgrade, rollback and re-upgrade passed. Proposed OpenAPI validated.

ADB listed emulator-5554 online. AAPT verified the existing isolated APK and AppAuth receiver. UI hierarchy showed the isolated guest Search foods field. The new Progress implementation was tested as a rendered Flutter widget and was not installed on Android.

## Phase 19

Dart formatting and Flutter analysis passed. Flutter default: 27 passed and one opt-in skip. Backend pytest: 10 passed and two opt-in skips. Disposable PostgreSQL 18.4: 10 passed including the expanded two-client Flutter TLS tracker and guest transfer journey. Alembic upgrade, rollback and re-upgrade passed. Both proposed and generated runtime OpenAPI validated.

The isolated x86_64 APK built offline in 1m50s and installed in the existing test package. A delayed first tracker tap required a fresh hierarchy and retry. The guest smoke visited Weight, Exercise and Water, added a 250 mL water record, verified it displayed in Progress and removed the synthetic record. Original FLEX and its data were preserved.

## Phase 20

- Disposable PostgreSQL 18.4 cloud suite passed 10 tests with 1 optional transport test skipped. Alembic round trip and separate database restore passed.
- Default backend suite passed 11 tests with 2 environment-gated tests skipped. Export isolation, pagination and response redaction passed.
- Flutter formatting passed for 24 files. Flutter analysis passed. Flutter tests passed 27 with 1 optional integration skipped.
- Standards validation passed for the design OpenAPI contract and the generated FastAPI OpenAPI schema. Docker Compose rendering passed, but the Linux Docker engine was unavailable for image execution.
- Staging database configuration tests confirm the CA requirement, CORS wildcard rejection and TLS mode override. The default backend suite totals 12 passed and 2 skipped.

## UI/UX and browser release — 20 November 2026

- Final Flutter regression: **35 passed, 1 optional transport integration skipped**. Coverage includes the existing auth/session/outbox/inbox/guest isolation tests, old-schema migration, saved meals/favorites/notes/preferences reopening, atomic copy rollback, post-commit-only notifications, decimal goal-weight preservation, and the search → preview → failed-save retry → committed diary journey.
- Responsive widget cases: 320×720, 390×844 at 2× text, and 1440×960 passed. The large-text ring fallback, navigation height and expanding dropdowns address verified overflow defects.
- Final Flutter analyzer: **no issues**. Formatter: **35 files, no changes**. `git diff --check` passed; Git emitted only local CRLF conversion notices.
- Backend with project `.deps`: **12 passed, 2 environment-gated skips**. Pytest-asyncio emitted an unset-loop-scope deprecation and Starlette emitted its HTTPX test-client deprecation. No backend cloud service or database was deployed.
- Browser release build passed with local engine resources. The build emitted an optional Cupertino icon-font discovery warning; the tested Material controls rendered correctly. iOS/Safari acceptance is not established.
- Isolated Android debug build passed with the cached Gradle 9.3.1 distribution, one worker and a bounded 1280 MiB heap. Artifact metadata/AAPT verified `dev.independent.fitness_diary.isolatedtest`, `1.1.0-dev`, version code `2`. Gradle/AGP/Kotlin emitted deprecation warnings; upgrading to Gradle/AGP 10 remains separate work.
- Isolated APK install succeeded. Cold launch returned a wait timeout. A subsequent device hierarchy identified **“System UI isn't responding”**, with zero FLEX nodes in that capture. Native runtime acceptance remains blocked by the emulator system dialog; the original FLEX package/data were not replaced or cleared.
- Live browser: USDA search and an Apple diary entry were verified locally before and after the v8 browser upgrade, then the synthetic entry was removed. On public HTTPS, a synthetic **250 mL** water entry survived reload and appeared in Progress; it was then removed and **0 mL / no water records** confirmed. Light appearance was applied and visually reviewed, then System appearance restored. No production/user records were uploaded.
- Figma structural audit: **52 editable screen/state/theme views**, zero non-Inter text nodes, zero complete-UI raster fills and no direct-child frame overflow. Dark/light Home, settings and custom-food screenshots reviewed. Prototype navigation and primary flows are linked; this is not an exhaustive interactive audit of every Figma layer.
- Public deployment **READY** in the authorized RED team: https://flex-nutrition-diary.vercel.app. Project `prj_X8R0beZCfPhFqMYXdeqKXGYqkeBc`; deployment `dpl_DouDkJ6pdiuWSJckKhBCJYhxRQUd`. A 33-file compiled browser artifact plus static hosting config was uploaded; no workspace source, credentials, SQLite files or screenshots were included.
- Public root, `main.dart.js`, SQLite WASM, worker and catalog returned **HTTP 200** with expected MIME types and `X-Content-Type-Options: nosniff`. Chrome console review during the tested live workflow returned no warning/error entries. Phone and desktop screenshots are stored under `docs/screenshots/`.
- OSV batch review checked **115 locked Pub/PyPI package versions**, with **no matching published advisories returned** and no pagination tokens. Evidence: `docs/DEPENDENCY_REVIEW.json`. This database lookup is not a source-code audit, secret-history scan or assurance against undisclosed vulnerabilities. The standalone pip-audit module was unavailable; the existing hosted CI audit was not run remotely.

External acceptance remains as listed in FEATURE_COMPLETENESS.md: real Auth0/cloud sync, erasure, interactive conflicts, signed Android release, physical ARM and assistive-technology checks, native reminders/tracker integrations, and browser offline reload. Hosted CI was updated to build/upload the browser artifact but was not executed remotely in this session.
