# Phase 17 Auth0 setup

No tenant or native client configuration was found in the FLEX workspace or current process environment. A tenant administrator must create or authorize a development Native application and Custom API. Keep production credentials outside this workflow.

1. Create a public Native application with Authorization Code and Refresh Token grants. Enable Universal Login, an appropriate login connection, signup, email verification and password recovery. Enable rotation and configure refresh lifetimes.
2. Register the exact callback dev.independent.fitness_diary.auth://callback. The Dart URI and Android manifest placeholder both use dev.independent.fitness_diary.auth. AAPT can verify the merged receiver in the built APK.
3. Register Allowed Logout URL dev.independent.fitness_diary.auth://logout for the Phase 18B full logout action. Ensure Auth0 discovery publishes end_session_endpoint. FLEX clears local credentials and attempts refresh-token revocation before invoking the browser flow.
4. Register a Custom API with a dedicated audience, RS256, the RFC 9068 access-token profile and offline access. The backend requires a client_id claim matching the Native application.
5. Set backend IDENTITY_ISSUER, IDENTITY_AUDIENCE, IDENTITY_CLIENT_ID, IDENTITY_JWKS_URL and DATABASE_URL in the development server environment. Derive issuer and JWKS from the configured tenant discovery document. Set Flutter public build defines FLEX_IDENTITY_ISSUER, FLEX_IDENTITY_AUDIENCE, FLEX_IDENTITY_CLIENT_ID and FLEX_API_URL. Keep FLEX_ENABLE_DIARY_SYNC false during authentication tests.
6. The emulator reaches the Windows host via 10.0.2.2. Use a trusted HTTPS certificate for the actual origin configured in FLEX. Test readiness and signed /v1/me before enabling the manual sync flag. No certificate-check bypass is needed.
