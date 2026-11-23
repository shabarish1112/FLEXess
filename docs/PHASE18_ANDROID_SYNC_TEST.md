# Phase 18 Android sync test

Real Android upload and download are blocked by missing development Auth0 and HTTPS settings. Host regression uses a disposable PostgreSQL cluster and signed synthetic accounts over loopback TLS. It does not prove Android can reach the configured backend or that the installed UI refreshes after a live commit.

Once the real identity gate passes, use separate authorized clients for USDA diary create, acknowledgement, download, edit, deletion, tombstones, restart recovery, signed-in isolation and visible Diary, Today, Nutrition and Progress totals. Keep guest records local and automatic sync disabled.

Guest-only device check passed in the isolated package. A USDA banana draft restored at 194 kcal after restart with no committed entry. The single committed Breakfast row survived a subsequent restart. Editing to three servings visibly changed the Diary total to 291 kcal. Deleting only the synthetic row restored the displayed total to 0 kcal. This was local SQLite, with no Auth0 or cloud transport on Android.

## Phase 18B

The isolated hosted-logout build passed the guest catalog preview and draft discard smoke after resuming from the running app. The original installation was preserved. Tenant settings remained absent, so live callback, browser session termination, Android Keystore access, HTTPS API calls and signed-in UI totals were not verified.
