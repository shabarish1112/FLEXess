from pathlib import Path
import runpy
import unittest

check = runpy.run_path(str(Path(__file__).with_name("phase18-auth0-preflight.py")))["check"]

ISSUER = "https://tenant.example.invalid/"
API = "https://api.example.invalid"
JWKS = ISSUER + ".well-known/jwks.json"
SETTINGS = {"FLEX_IDENTITY_ISSUER": ISSUER, "FLEX_IDENTITY_AUDIENCE": "urn:flex:dev",
            "FLEX_IDENTITY_CLIENT_ID": "public-client", "FLEX_API_URL": API}


class PreflightTest(unittest.TestCase):
    def test_public_discovery_readiness_and_unauthenticated_rejection(self):
        routes = {
            ISSUER + ".well-known/openid-configuration": (200, {"issuer": ISSUER, "end_session_endpoint": ISSUER + "oidc/logout", "jwks_uri": JWKS}),
            JWKS: (200, {"keys": [{"kty": "RSA", "use": "sig", "alg": "RS256",
                                 "kid": "fixture", "n": "fixture", "e": "AQAB"}]}),
            API + "/health/ready": (200, {"status": "ok"}),
            API + "/v1/me": (401, None),
        }
        check(SETTINGS, routes.__getitem__)
        routes[API + "/v1/me"] = (200, {})
        with self.assertRaisesRegex(ValueError, "did not reject"):
            check(SETTINGS, routes.__getitem__)

    def test_missing_settings_never_make_network_requests(self):
        with self.assertRaisesRegex(ValueError, "FLEX_IDENTITY_CLIENT_ID"):
            check({}, lambda _: self.fail("Unexpected network request"))

    def test_plaintext_key_url_is_rejected_before_fetch(self):
        def discovery(url):
            self.assertEqual(url, ISSUER + ".well-known/openid-configuration")
            return 200, {"issuer": ISSUER, "end_session_endpoint": ISSUER + "oidc/logout", "jwks_uri": "http://other.example.invalid/keys"}
        with self.assertRaisesRegex(ValueError, "HTTPS JWKS"):
            check(SETTINGS, discovery)

    def test_missing_logout_endpoint_blocks_release_gate(self):
        with self.assertRaisesRegex(ValueError, "end-session"):
            check(SETTINGS, lambda _: (200, {"issuer": ISSUER, "jwks_uri": JWKS}))
