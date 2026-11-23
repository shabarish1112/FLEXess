# FLEX 2 verification

Verification is being updated during implementation. Existing consumer release evidence remains in `TEST_RESULTS.md`; it does not establish FLEX 2 authentication/admin acceptance.

Backend suites cover signed Firebase JWT claim rejection, legacy-provider compatibility, owner preservation on linking, rejection of existing-account merges, anonymous/consumer/support/admin boundaries, no health payload exposure in directory responses, suspension enforcement, audit creation, catalog revision checks, atomic import and migration backfill.

Flutter checks include the existing consumer regression suite and new service-error redaction, HTTPS/redirect rules, six admin sections at phone/desktop widths, food form validation, unconfigured access rejection and reduced-motion ring behavior.

Live Google login and approved administrator reads now pass in both environments. Native Android Google login, fictional OTP, live cross-device linking/sync, sensitive administrator write acceptance and cross-browser coverage remain unverified.

## Recorded checks — 2026-11-20

- Backend `python -m pytest -q`: **24 passed, 2 skipped**. Skips cover optional PostgreSQL/TLS integration conditions in the general SQLite suite. Pytest/Starlette emitted existing dependency deprecation warnings.
- Isolated PostgreSQL 18.4 smoke: **10 passed, 1 optional TLS test skipped**; concurrent ownership/sync operations passed. Alembic reached 0003, preserved the legacy fixture and restored all nine application/version tables into a separate database. Temporary cluster was shut down cleanly.
- Flutter analyzer: **no issues**. Formatting and JSON configuration parsing passed. `git diff --check` passed.
- Release web compilation: consumer `build/consumer` and final admin `build/admin` passed. Both used locally bundled web renderer resources. Flutter emitted a Cupertino font expectation warning; application icons use Material Icons, and no missing application icon was observed in widget checks. WebAssembly dry-run passed; a deployed Wasm build was not tested.
- Locked package OSV review: **129 Pub/PyPI versions, no returned advisories**. See `FLEX_2_DEPENDENCY_REVIEW.json`. This does not cover native Gradle dependencies or prove absence of vulnerabilities.
- Earlier full Flutter suite: **52 passed, 1 opt-in authenticated PostgreSQL/TLS integration test skipped**. Includes responsive admin sections at 390/1440 pixels, global search/record opening, inline food validation, invalid-phone rejection before SDK access, safe API errors, unconfigured access rejection and reduced-motion behavior.
- Isolated Android debug APK built successfully after a sequential online retry: `mobile/build/releases/FLEX-2.0.0-dev-x86_64-isolated-debug.apk`. Package `dev.independent.fitness_diary.isolatedtest`, version 2.0.0-dev (3). Runtime authentication remains unverified. Later wording changes are not included in this APK.

- Latest targeted admin/phone regression suite: **18 passed**, including rejection of real phone numbers before Firebase SDK calls. Subsequent platform-specific web artifacts were rebuilt with observed backend URLs and deployed.


## Live checks — 2026-11-21

- Both Render Free APIs: HTTPS liveness/readiness 200, anonymous administrator endpoint 401. Production untrusted CORS preflight returned 400 without an allow-origin header. Development consumer/admin origins passed preflight.
- Fresh consumer/admin release web builds passed and deployed to separate development Spark Hosting sites. Live Google consumer login succeeded and created one backend account with the expected development Firebase issuer. Approved development and production administrator overview access passed; development user directory and role-assignment audit also passed.


- Final Flutter regression suite (2026-11-21): **53 passed, 1 optional authenticated PostgreSQL/TLS integration skipped**. Analyzer: **no issues**. All four environment-specific consumer/admin web releases built and published successfully.
- Configured Android build: **BUILD SUCCESSFUL**, 305 tasks, isolated package dev.independent.fitness_diary.isolatedtest, version **2.0.1-dev (4)**. Artifact: mobile/build/releases/FLEX-2.0.1-dev-x86_64-isolated-debug.apk; SHA-256 CFC61EE409988CF479531FAE47AB7BD1AE95360F9BED75ECA08153C2AE30B0F4. ZIP inspection verified the development API/Firebase identifiers and SMS guard. Flutter engine ABI: **x86_64**, intended for emulator testing; no physical-phone or native login pass is claimed.
- Production admin session restored after a full reload and fetched real metrics. Both production frontend origins returned HTTP 200 with nosniff and DENY frame headers. Exact production admin CORS passed.
- Live browser viewport override did not change the observed 1366x543 viewport; no live 390px acceptance is claimed. Responsive widget coverage at 320/390/1440px passed.


- Credential-exposure self-check: all four compiled frontend bundles and the x86_64 APK contained their intended environment endpoints and none of the Neon owner/runtime passwords. Ignored client configuration files contained no database/private-key fields.


- Emulator install/launch approval is pending. The first install request was rejected by automatic approval review for missing explicit installation/replacement authorization; no mutation occurred. REA's read-only device inspection also could not locate adb on its server PATH. The installed Android SDK adb is available by absolute path.


- ARM64 phone build: **BUILD SUCCESSFUL** in 4m 6s. Saved `mobile/build/releases/FLEX-2.0.2-dev-arm64-isolated-debug.apk`, isolated package `dev.independent.fitness_diary.isolatedtest`, version **2.0.2-dev (5)**, min SDK 24. SHA-256 `137BCD78C6AD18D8C92F7D4482E70BFCB85B69EED2BA76143B98439EACC25FC6`. Verified the ARM64 Flutter engine, development endpoint/project, SMS guard and absence of Neon passwords. This is a development debug APK, not a signed production release; physical-device execution remains unverified.
