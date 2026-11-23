# Phase 15 security

The integration harness uses signed synthetic access tokens and a temporary loopback TLS endpoint. The Flutter client verifies the supplied trust anchor. Production certificate verification is unchanged by default. No credentials are committed or sent to an external service. Runtime mobile sessions, provider configuration, and public rollout remain outside this checkpoint.
