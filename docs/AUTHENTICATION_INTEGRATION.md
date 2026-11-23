# Authentication integration

Firebase is added alongside the existing Auth0 verifier. Configure `FIREBASE_PROJECT_ID` on the backend; all four legacy OIDC settings may remain configured. A Firebase token must pass Google's RSA signature, key ID, exact issuer/project audience, expiry, issued-at, subject and authentication-time validation. The client cannot assert a backend owner ID or role.

`linked_identity` maps `(issuer, subject)` to the existing backend UUID. Migration 0003 backfills legacy mappings. The original `app_user` identifiers and all owned-record/receipt keys remain unchanged. Newly observed identities create consumer accounts only. Email addresses never drive linking.

`POST /v1/account/link` requires the signed-in token and a second signed credential. Both must carry authentication within five minutes. Existing accounts are not automatically merged, even when empty or when emails match. A unique identity constraint resolves concurrent claims without transferring records.

Flutter uses Firebase Auth persistence and token refresh. Web Google uses the SDK popup; Android uses Google Sign-In 7.x and Firebase credentials. Phone uses a country-code selector, E.164 validation, SDK web reCAPTCHA/native verification, a six-digit code, 60-second client resend cooldown and mapped error states. Firebase service-side quotas remain authoritative; client cooldown alone is not abuse protection.

Within one Firebase user, Google/phone linking uses provider credential ownership verification. Linking an existing Auth0 account calls the backend link endpoint before asking Firebase for a backend UUID. Existing account SQLite and explicit guest-transfer paths are reused. Auth0 sessions without `auth_time` cannot authorize linking; obtain a fresh provider token with the claim rather than weakening the policy.

Build inputs: `FLEX_FIREBASE_PROJECT_ID`, `FLEX_FIREBASE_APP_ID`, `FLEX_FIREBASE_API_KEY`, `FLEX_FIREBASE_SENDER_ID`, optional `FLEX_FIREBASE_AUTH_DOMAIN`, Android `FLEX_GOOGLE_SERVER_CLIENT_ID`, and `FLEX_API_URL`. Use platform-specific Firebase app IDs. Public client API keys are not service-account keys; never embed administrative credentials.

The ₹0 deployment policy supersedes real-SMS usage: production is Google-only. Phone verification is accepted only when `FLEX_ENVIRONMENT=development`, `FLEX_FIREBASE_PHONE_TESTS=true` and the entered number is in `FLEX_FIREBASE_TEST_PHONE_NUMBERS`. Unlisted/real numbers are rejected before calling Firebase. Codes are configured in Firebase, never embedded in the app. Development Google is enabled on Spark; real phone/SMS service is not enabled. Current resource state is in `deployment-status.json`.

Known limit: signature verification does not query provider revocation or disabled-user state. Backend suspension is enforced on every request, but externally revoked ID tokens can remain valid until expiry. Privileged production rollout needs a revocation strategy and acceptance tests. Live Google OAuth and approved Admin access passed in both environments; production admin session restoration after reload passed. Fictional OTP, native login and cross-device credential linking remain unverified.

Primary documentation: [Firebase ID-token verification](https://firebase.google.com/docs/auth/admin/verify-id-tokens), [Flutter federated sign-in](https://firebase.google.com/docs/auth/flutter/federated-auth), [phone authentication](https://firebase.google.com/docs/auth/flutter/phone-auth), [account linking](https://firebase.google.com/docs/auth/flutter/account-linking).

