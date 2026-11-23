# Phase 18 Auth0 live test

No development tenant, public native client ID, audience, or configured HTTPS API was found in local FLEX settings or the current process environment. No live registration, login, recovery, callback, logout, Keystore or account-switch test was possible.

## Tenant-owner actions

- Provision or authorize a development Native application, database connection and Custom API. Enable Universal Login, signup, email verification/recovery, Authorization Code with PKCE, Refresh Token, token rotation, and API offline access. Set the API to RS256 and the RFC 9068 access-token profile.
- Register the Allowed Callback URL dev.independent.fitness_diary.auth://callback. This matches the Flutter AppAuth callback. AAPT checks the merged scheme on the APK.
- Register Allowed Logout URL dev.independent.fitness_diary.auth://logout. Enable RP-Initiated Logout endpoint discovery if end_session_endpoint is absent. The full logout path clears local storage, attempts refresh-token revocation and invokes AppAuth endSession through Auth0. Both native URLs share the merged AppAuth scheme.
- Make the development API available from Android on a trusted HTTPS origin. Emulator host routing uses 10.0.2.2 where appropriate. The certificate must match the selected origin.

## Local execution once configured

Set public FLEX_IDENTITY_ISSUER, FLEX_IDENTITY_AUDIENCE, FLEX_IDENTITY_CLIENT_ID and FLEX_API_URL for the app and preflight. Use tenant discovery for backend IDENTITY_ISSUER and IDENTITY_JWKS_URL. Also configure IDENTITY_AUDIENCE, IDENTITY_CLIENT_ID and DATABASE_URL on the backend. Do not provide passwords or keys to the preflight. Run python scripts/phase18-auth0-preflight.py. It checks HTTPS discovery including the end-session endpoint, compatible signing key metadata, API readiness and unsigned rejection. It cannot confirm client grants or prove a browser flow.

Build the isolated Android variant with the public definitions and sync disabled. Use a tenant-authorized test account to verify signup, callback, /v1/me, restart restoration, token renewal, password recovery, local logout and account switching. Then enable only manual sync for the acceptance journey.

## Phase 18B hosted logout

Sign out clears the local session and attempts refresh-token revocation. Sign out of browser too additionally calls Flutter AppAuth endSession. The ID token hint is kept only in memory if supplied by the provider, and the public client_id is passed for the Auth0 return URL. The account scope is cleared before either network operation. A cancellation cannot restore that scope. Live browser and Android Keystore behavior still require the development tenant.

## Phase 18C dependency check

At Git 37b7130 the preflight ran once and exited 1. FLEX_IDENTITY_ISSUER, FLEX_IDENTITY_AUDIENCE, FLEX_IDENTITY_CLIENT_ID and FLEX_API_URL were missing. Tenant endpoints, allow-list settings and actual browser behavior could not be verified. Do not rerun the live preflight until public development configuration has been supplied.
