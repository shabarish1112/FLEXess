# Known issues

The real catalog release has not been bundled. The import pipeline currently supports four nutrients and one 100 g reference serving for USDA. Dedicated macro goals and Weight, Water, Exercise, and Progress screens are pending. PostgreSQL tools are installed, but transient initdb failed opening the password file. Managed authentication, authorization integration tests, sync, ARM/release builds, and accessibility testing remain open.

## Phase 10

Foundation Foods has incomplete nutrition and serving data. Unknown values remain missing. Exercise credit uses approximate MET categories and is opt-in. Release signing and physical device validation remain pending.

## Phase 11

System UI ANR and unreliable UIAutomator capture can block the device journey even when ADB commands succeed. Managed identity and sync remain disabled.

## Phase 12

Live account UI, secure storage, account switching, explicit guest migration and applying the remote change feed remain pending. The off-by-default outbox covers diary writes only.

Phase 14 legacy diary snapshots lack measured serving data. They are readable with historical totals and blocked from recalculation. Sync remains disabled in the application UI.

Phase 15 leaves ordinary-user sync disabled. Account sign-in, secure sessions, visible device refresh, tracker synchronization, guest transfer and refreshing an open Progress route remain pending.

Phase 16 requires a development Auth0 tenant and Android verification. Automatic sync scheduling, live secure storage checks, tracker sync and guest transfer remain pending.

Phase 17 live provider and authenticated Android sync need the development identity and API settings documented in PHASE17_AUTH0_SETUP.md.

Phase 18 live Auth0 Android acceptance remains blocked on tenant Native client audience and HTTPS configuration. No physical ARM64 device was attached.

Hosted Auth0 logout requires the exact logout URL allow-list and end_session_endpoint discovery. Live browser state and Android cloud flows remain unverified.

Phase 18C live acceptance is blocked by absent development Auth0 and HTTPS public configuration. The installed APK was inspected but does not include the new Phase 19 Progress change.

Phase 19 leaves real Auth0 and Android cloud acceptance blocked. Interactive conflict resolution is pending. Real-device consent and tracker sync require development identity configuration.

## Phase 20

- Docker image execution, private staging, hosted CI, interactive conflict resolution, account erasure and native tracker CRUD require verification. Auth0 Android cloud acceptance remains externally blocked.
