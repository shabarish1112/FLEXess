from dataclasses import dataclass
from typing import Protocol
from urllib.parse import urlsplit
import re
import time

import jwt


class InvalidIdentity(Exception):
    pass


@dataclass(frozen=True)
class Identity:
    issuer: str
    subject: str
    authenticated_at: int | None = None


class IdentityVerifier(Protocol):
    def verify(self, token: str) -> Identity: ...


class ManagedIdentityVerifier:
    """Validates RFC 9068 access tokens from a configured OIDC issuer."""

    def __init__(self, issuer: str, audience: str, jwks_url: str, client_id: str):
        for url in (issuer, jwks_url):
            parsed = urlsplit(url)
            if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password:
                raise ValueError("Identity issuer and JWKS require HTTPS URLs")
        self.issuer, self.audience, self.client_id = issuer, audience, client_id
        self.keys = jwt.PyJWKClient(jwks_url, timeout=5, lifespan=300)

    def verify(self, token: str) -> Identity:
        if len(token) > 8192:
            raise InvalidIdentity()
        try:
            header = jwt.get_unverified_header(token)
            if header.get("typ") not in ("at+jwt", "application/at+jwt") or header.get("alg") != "RS256":
                raise InvalidIdentity()
            key = self.keys.get_signing_key_from_jwt(token).key
            claims = jwt.decode(
                token, key, algorithms=["RS256"], issuer=self.issuer,
                audience=self.audience, options={"require": ["exp", "iat", "sub", "iss", "aud", "jti", "client_id"]},
            )
        except (jwt.PyJWTError, TypeError, ValueError) as exc:
            raise InvalidIdentity() from exc
        if not claims["sub"] or len(claims["sub"]) > 255 or not claims["jti"] or claims["client_id"] != self.client_id:
            raise InvalidIdentity()
        return Identity(self.issuer, claims["sub"], claims.get("auth_time"))


class FirebaseIdentityVerifier:
    """Verify Firebase ID tokens against the project's Google signing keys."""

    def __init__(self, project_id: str):
        if not re.fullmatch(r"[a-z][a-z0-9-]{4,28}[a-z0-9]", project_id):
            raise ValueError("Use an exact Firebase project ID")
        self.project_id = project_id
        self.issuer = f"https://securetoken.google.com/{project_id}"
        self.keys = jwt.PyJWKClient(
            "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com",
            timeout=5, lifespan=300,
        )

    def verify(self, token: str) -> Identity:
        if len(token) > 8192:
            raise InvalidIdentity()
        try:
            header = jwt.get_unverified_header(token)
            if header.get("alg") != "RS256" or not header.get("kid"):
                raise InvalidIdentity()
            key = self.keys.get_signing_key_from_jwt(token).key
            claims = jwt.decode(token, key, algorithms=["RS256"], issuer=self.issuer,
                                audience=self.project_id,
                                options={"require": ["exp", "iat", "sub", "iss", "aud", "auth_time"],
                                         "strict_aud": True})
            authenticated = claims["auth_time"]
            if (not claims["sub"] or len(claims["sub"]) > 128
                    or type(authenticated) is not int or authenticated < 0
                    or authenticated > time.time()):
                raise InvalidIdentity()
        except (jwt.PyJWTError, TypeError, ValueError) as exc:
            raise InvalidIdentity() from exc
        # shortcut: provider revocation is not queried here; use short token lifetimes and local suspension.
        return Identity(self.issuer, claims["sub"], authenticated)


class ConfiguredIdentityVerifier:
    def __init__(self, verifiers: list[IdentityVerifier]):
        self.verifiers = verifiers

    def verify(self, token: str) -> Identity:
        if len(token) > 8192:
            raise InvalidIdentity()
        try:
            # Unverified issuer only selects a fixed verifier; signature validation still follows.
            issuer = jwt.decode(token, options={"verify_signature": False}).get("iss")
        except (jwt.PyJWTError, TypeError, ValueError) as exc:
            raise InvalidIdentity() from exc
        for verifier in self.verifiers:
            if getattr(verifier, "issuer", None) != issuer:
                continue
            try:
                return verifier.verify(token)
            except InvalidIdentity:
                continue
        raise InvalidIdentity()
