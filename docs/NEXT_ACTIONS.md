# Next actions

1. Review one official USDA release and rejected rows using scripts/import_usda.py. Load a curated catalog into mobile/assets/catalog.json and verify imported food search at scale and on-device attribution.
2. Extend the food model to expose additional nutrient and portion metadata. Expand the existing energy goal into persisted macro targets.
3. Implement Weight, Water, Exercise and Progress based on locally stored records.
4. Verify backend migrations/readiness on an isolated authenticated PostgreSQL instance. Test ownership and idempotency before enabling remote diary.
5. Validate a physical ARM release build and accessibility.

## Phase 10 continuation

Run the Android x86_64 emulator catalog smoke with scripts/phase10-catalog-smoke.ps1. Then exercise the Weight, Water and Exercise add/edit/delete flows and verify dated Goals and Progress after a restart. For release, validate a signed arm64 build on a physical device.
Before retrying, run adb -s emulator-5554 shell echo FLEX and adb -s emulator-5554 shell uiautomator dump /sdcard/flex-p10.xml separately. Check the diary for a previously created smoke entry before writing.

## Phase 11 continuation

1. Confirm FLEX has window focus and run an individual UIAutomator dump. Then run scripts/phase10-catalog-smoke.ps1 with -Adb and the Platform-Tools adb.exe path. Add -FromDiary if Diary is already visible. This opens and discards a temporary serving draft. Check for an existing matching draft first.
2. Before testing diary writes and tracking, use a disposable emulator or isolated synthetic data. Record baseline totals and confirm restart, edit, and cleanup. Keep the existing installation and SQLite data intact.
3. Validate identity provider settings and implement token verification and two-user negative tests. Then add reversible ownership migrations tested on disposable PostgreSQL before enabling any sync.
Confirmed: USDA preview, one Breakfast commit, restart persistence and cleanup. Next device operation: on a separate disposable emulator, capture baseline totals, commit and edit a guarded USDA row, compare totals, then delete it. Follow with Goals, Weight, Water, Exercise and Progress and negative cases from PHASE11_DEVICE_TEST_MATRIX.csv.

## Phase 12 continuation

1. Run the Android APK only on a disposable AVD for the Phase 12 device matrix. Verify edit and total restoration, draft restart, and tracking CRUD.
2. Configure Phase 12 managed identity on an isolated tenant and run native sign-in, reset, expiry, refresh and logout. Keep guest data outside account storage. See PHASE12_AUTHENTICATION_IMPLEMENTATION.md.
3. Connect the account-specific outbox only after authenticated mobile state is verified. Add opted-in guest transfer, tracking enqueue and applying the remote changes feed.
Android resume: with sufficient memory available run offline assembleDebug with -Ptarget-platform=android-x64 -PflexIsolatedDebug=true. Verify package dev.independent.fitness_diary.isolatedtest with aapt dump badging before installing it. Then run scripts/phase10-catalog-smoke.ps1 -Serial emulator-5554 -Isolated -Relaunch -CommitTestEntry with the SDK ADB path. The existing FLEX package must keep its original database.

## Phase 13

Next operation: project validated diary inbox records into the account diary tables in the same SQLite transaction as the cursor. Preserve nutrient snapshots and block projection while a local operation is unresolved. Then run two SQLite clients against a disposable authenticated backend. Continue the provider and Android gates independently.

## Phase 14

Run authenticated FastAPI/PostgreSQL with two separate account SQLite files. Upload the first device outbox via HTTPS and apply the actual change feed on the second. Add a Riverpod refresh hook after commit and verify selected-date totals and conflict recovery. Keep ordinary users on guest mode.

## Phase 15

Reproduce the transport integration with FLEX_RUN_FLUTTER_SYNC=1 and python scripts/phase12-postgres-smoke.py C:/src/PostgreSQL/18/bin. Next, configure a development identity tenant and secure mobile sessions, then use the account-only refresh in a disposable Android build. Verify visible Diary, Today, Nutrition and open Progress before enabling live sync.

## Phase 16

Provision the development Auth0 native client and API using PHASE16_IDENTITY_PROVIDER_DECISION.md. Build with the four public configuration defines and leave FLEX_ENABLE_DIARY_SYNC off for the first Android launch. Verify browser signup, recovery, Keystore restoration and logout on an isolated package before enabling the manual sync flag for the two-device diary checks.

## Phase 17

Provision the Native client and Custom API using PHASE17_AUTH0_SETUP.md. Load only the public build defines, verify the merged AppAuth receiver and test the disposable Android build with sync off. Confirm /v1/me, hosted recovery and Keystore restoration before enabling manual diary sync for synthetic accounts.
Android resume: restore normal System UI focus on emulator-5554, then resume the guest smoke against dev.independent.fitness_diary.isolatedtest. Leave the original FLEX package and data in place.

## Phase 18

Tenant owner: provision development Auth0 and HTTPS settings in PHASE18_AUTH0_LIVE_TEST.md. Then run python scripts/phase18-auth0-preflight.py and build the configured isolated APK. Verify signed-in restore and logout before enabling the manual diary flag for the two-client device journey. Leave automatic sync off.
The isolated guest case is complete and its synthetic entry was removed. Next run the public preflight with the real development configuration, then verify the browser callback on a configured isolated build.

## Phase 18B

Tenant owner: configure the Auth0 Native client, connection, code/refresh grants and token rotation. Allow dev.independent.fitness_diary.auth://callback for login and dev.independent.fitness_diary.auth://logout for logout. Publish the RP-Initiated Logout discovery endpoint and configure the development API audience and trusted HTTPS origin. Run the public preflight before building the configured isolated APK. Verify login, restart, hosted logout and a second sign-in before manual sync acceptance.

## Phase 18C and Phase 19

Auth0 and the development HTTPS origin are external blockers. Resume the live preflight only after the four public values are configured. Then validate the isolated browser login and logout lifecycle, Android /v1/me, and the separate-client diary acceptance journey. Phase 19 adds an account-store notification to refresh an already-open Progress view after SQLite commits a diary projection. Verify this path next on the configured isolated Android installation.

## Phase 19 tracker and guest transfer

Resume the live Phase 18 gate only once the development Auth0 and HTTPS public settings are supplied. Then verify tracker reconciliation and guest consent on a configured isolated device with the separate flags. Exercise account-scope changes during the transfer dialog and check tracker edit/delete and real acknowledgement recovery. Keep automatic sync off.
Verified on Android: guest tracker navigation, water quick-add, Progress read and synthetic cleanup. Next verify signed-in tracker projection and the consent screen on the isolated Android build when development settings become available. Test per-kind edit/delete, conflict review and same-date goal resolution before rollout.

## Phase 20 continuation

Next operation: implement and test transaction-safe conflict resolution against the existing outbox. Verify each resolution choice with divergent revisions on two local test stores. Run tracker CRUD with investigator-created synthetic records on the isolated Android package. Verify the container on a running Docker engine, then verify staging with real Auth0, HTTPS and managed PostgreSQL before accepting Android cloud sync.
