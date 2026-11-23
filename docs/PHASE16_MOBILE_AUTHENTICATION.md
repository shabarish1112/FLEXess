# Phase 16 mobile authentication

Account actions appear only with a configured HTTPS issuer and API, client ID and audience. AppAuth opens Universal Login for sign-in or signup. Password recovery is available from the hosted login page when enabled on the tenant. FastAPI /v1/me verifies the token and returns the UUID that selects the local account database. The root navigation resets when the account changes. Guest remains usable without configuration. No tenant or native client settings were available for live validation.
