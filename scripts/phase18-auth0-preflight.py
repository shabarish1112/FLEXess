"""Check FLEX public Auth0 and HTTPS settings without using credentials."""

import json
import os
import sys
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, build_opener

SETTINGS = (
    "FLEX_IDENTITY_ISSUER",
    "FLEX_IDENTITY_AUDIENCE",
    "FLEX_IDENTITY_CLIENT_ID",
    "FLEX_API_URL",
)
MAX_RESPONSE = 1024 * 1024


class PreflightError(ValueError):
    pass


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def https_origin(value):
    parsed = urlsplit(value)
    if (parsed.scheme != "https" or not parsed.hostname or parsed.username is not None
            or parsed.path not in ("", "/") or parsed.query or parsed.fragment):
        raise PreflightError("Expected an HTTPS origin without credentials, query or fragment.")


def get(url):
    try:
        with build_opener(NoRedirect()).open(url, timeout=10) as response:
            data = response.read(MAX_RESPONSE + 1)
            if len(data) > MAX_RESPONSE:
                raise PreflightError("Response exceeded the preflight size limit.")
            return response.status, json.loads(data)
    except HTTPError as error:
        error.close()
        return error.code, None


def check(environment, fetch=get):
    missing = [name for name in SETTINGS if not environment.get(name, "").strip()]
    if missing:
        raise PreflightError("Missing public settings: " + ", ".join(missing))
    issuer, _, _, api = (environment[name] for name in SETTINGS)
    https_origin(issuer)
    https_origin(api)

    status, discovery = fetch(issuer.rstrip("/") + "/.well-known/openid-configuration")
    if status != 200 or not isinstance(discovery, dict) or discovery.get("issuer") != issuer:
        raise PreflightError("OIDC discovery failed or the issuer does not match exactly.")
    logout = discovery.get("end_session_endpoint")
    if not isinstance(logout, str):
        raise PreflightError("OIDC discovery did not publish an end-session endpoint.")
    logout_uri = urlsplit(logout)
    if (logout_uri.scheme != "https" or not logout_uri.hostname
            or logout_uri.username is not None or logout_uri.query or logout_uri.fragment):
        raise PreflightError("Expected a public HTTPS end-session endpoint.")
    jwks = discovery.get("jwks_uri")
    if not isinstance(jwks, str):
        raise PreflightError("OIDC discovery did not publish a JWKS URI.")
    parsed = urlsplit(jwks)
    if (parsed.scheme != "https" or not parsed.hostname or parsed.username is not None
            or parsed.query or parsed.fragment):
        raise PreflightError("Expected a public HTTPS JWKS URI.")
    status, keys = fetch(jwks)
    if status != 200 or not isinstance(keys, dict) or not isinstance(keys.get("keys"), list):
        raise PreflightError("The JWKS response was invalid.")
    if not any(isinstance(key, dict) and key.get("kty") == "RSA"
               and key.get("use") in (None, "sig") and key.get("alg") in (None, "RS256")
               and all(isinstance(key.get(field), str) and key[field] for field in ("kid", "n", "e"))
               for key in keys["keys"]):
        raise PreflightError("No compatible RSA signing key was advertised.")

    status, ready = fetch(api.rstrip("/") + "/health/ready")
    if status != 200 or ready != {"status": "ok"}:
        raise PreflightError("The FLEX API readiness check failed.")
    status, _ = fetch(api.rstrip("/") + "/v1/me")
    if status != 401:
        raise PreflightError("The FLEX identity endpoint did not reject an unauthenticated request.")


def main():
    try:
        check(os.environ)
    except (ValueError, URLError, OSError) as error:
        if isinstance(error, PreflightError):
            print(str(error), file=sys.stderr)
        else:
            # Never print network exception URLs, which may be user-controlled.
            print("Public HTTPS preflight failed. Check TLS and endpoint accessibility.", file=sys.stderr)
        return 1
    print("Discovery, hosted logout endpoint, RSA JWKS, API readiness and unauthenticated rejection passed.")
    print("Tenant client registration and real login still require device verification.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
