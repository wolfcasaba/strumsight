#!/usr/bin/env python3
"""Production/internal-cohort smoke test (E12-R31, round brief §0.0.1 P1-P5).

Runs a fixed set of read-mostly checks against a deployed backend and a
local artifact tree, and prints one PASS/FAIL line per check. Never takes a
credential as a CLI argument (§5.1) — the account password is read from an
environment variable named by ``--password-env`` (default
``STRUMSIGHT_SMOKE_PASSWORD``), never from ``sys.argv``, so it never shows
up in shell history or a process listing (``ps``). No check output ever
includes the password or the bearer token, and the body of an authenticated
response (``/auth/me``, ``/settings``, ``/community/feed``) is never
printed — only status codes and the server's own ``reason``/``status``
fields (never secret, see the ``/health/ready`` traffic-gate shape below).
``--base-url`` must be ``https://`` (round brief MAJOR-3, exit 2 fail-closed
if not) so the password and the bearer token are never sent over a plain
``http://`` wire; ``--allow-insecure-http`` opts a local/staging run back
into plain HTTP.

Standard library only (`urllib.request`), matching
`tool/release/verify_signing_policy.py`'s precedent: this tool has to run
standalone against a real deploy target, where a third-party package is not
guaranteed to be installed.

Checks (all run independently — one failing does not skip the rest, so a
single invocation reports the full picture in one pass):

  readiness       GET  /health/ready               (§0.0.1 P1 — NOT /readyz)
  auth_login      POST /auth/login                  (§0.0.1 P5)
  auth_me         GET  /auth/me  (bearer from login) (§0.0.1 P5)
  settings        GET  /settings (bearer)            (§0.0.1 P5)
  community_feed  GET  /community/feed (bearer)      (§0.0.1 P5 — 200 or 404
                  both PASS: a smoke account with no community profile
                  legitimately 404s (`app/community/routers/feed.py`'s own
                  docstring), and so does a deploy where the Community
                  router isn't mounted at all (true of this round's tree) —
                  a status code alone can't tell those two apart, so a 404
                  detail says so instead of claiming "reachable")
  lab_routes_absent  POST /diagnostics, GET /diagnostics/health,
                  GET /download must ALL be 404 (ADR 0061, §0.0.1 P3) — the
                  legacy reference is
                  `backend/tests/test_hardening.py::TestProdHardening::
                  test_prod_defaults_do_not_register_lab_routes`. Also
                  probes POST /download (a method the route, if registered,
                  never exposes): a route that is truly absent 404s any
                  method, but a route that exists with `apk_download_enabled`
                  on (even with no APK staged, itself a plain 404) answers a
                  wrong method with 405 — so this wrong-method probe is the
                  only way to fail closed on "route exists but nothing is
                  staged yet" (round brief MAJOR-1; a status-code-only check
                  on GET /download alone cannot tell that apart from "route
                  absent", since both read 404).
  fingerprint     the `--signing-certificate` sidecar JSON's
                  `sha256Fingerprint` key must match `--expected-fingerprint`
                  (§0.0.1 P2 — the release manifest has NO signing field,
                  the sidecar is the only source of truth). A missing file,
                  unparsable JSON, or a missing `sha256Fingerprint` key is a
                  FAILURE, never a silent/fail-open pass.
  model_manifest  `--asset-root`/assets/ml/model_manifest.json must exist
                  and parse as JSON — a LOCAL artifact check, never an HTTP
                  fetch (§0.0.1 P4: the model manifest is a bundled asset,
                  not a backend endpoint).

A `GET /health/ready` 503 with `{"status": "not_ready", "reason": ...}` is
the ADR 0449 D1 traffic gate, not a business-endpoint bug (§0.0.1 P1) — any
business check (auth/settings/community) that hits the same shape reports
that reason directly (`"traffic gate active (not_ready): <reason>"`) instead
of a generic "unexpected status 503".

Exit codes:
  0  every check passed
  1  at least one check failed (a validation/deploy-health finding)
  2  usage error: bad/missing CLI arguments, or the `--password-env` named
     environment variable is unset or empty (fail-closed: no argument
     spelling of a password is ever accepted, so an operator who forgets to
     export it gets a clear, structured error instead of a checked-in
     temptation)
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit

DEFAULT_PASSWORD_ENV = "STRUMSIGHT_SMOKE_PASSWORD"

_LAB_ROUTES: tuple[tuple[str, str], ...] = (
    ("POST", "/diagnostics"),
    ("GET", "/diagnostics/health"),
    ("GET", "/download"),
    # Wrong-method probe (round brief MAJOR-1): if /download is registered
    # (apk_download_enabled=True), only GET is exposed, so POST answers 405
    # Method Not Allowed — a status a truly-absent route can never produce
    # (an unmatched path 404s regardless of method). This is what catches
    # "registered but no APK staged yet", which itself 404s on GET and would
    # otherwise be indistinguishable from "route absent".
    ("POST", "/download"),
)


class _HttpError(Exception):
    """A request could not even reach the server (connection refused, DNS
    failure, timeout) — distinct from an HTTP response with a bad status,
    which is a normal (if failing) `Response`."""


@dataclass(frozen=True)
class Response:
    status_code: int
    body: bytes

    def json(self) -> Any:
        return json.loads(self.body.decode("utf-8"))


@dataclass(frozen=True)
class CheckResult:
    name: str
    ok: bool
    detail: str


def _dumps(payload: dict) -> bytes:
    return json.dumps(payload).encode("utf-8")


class _NoRedirectHandler(urllib.request.HTTPRedirectHandler):
    """Blocks redirect-following (round brief MINOR-1): `urllib`, unlike
    `requests`/`httpx`, does NOT strip the `Authorization` header on a
    host-changing redirect — a 3xx response from `--base-url` could hand the
    bearer token (or a POST body containing the password) to a different
    host. This smoke tool exists to measure the GIVEN `--base-url`, not to
    follow wherever it points, so a redirect is reported as its own status
    code (e.g. 302) — an "unexpected status" failure — instead of being
    followed."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


_NO_REDIRECT_OPENER = urllib.request.build_opener(_NoRedirectHandler)


class UrllibClient:
    """A minimal HTTP client with the same `.get(path, headers=)` /
    `.post(path, json=, headers=)` -> `Response(status_code, .json())` shape
    as `fastapi.testclient.TestClient` (httpx-based) — so `run_checks`
    below works unmodified against a real deploy (this class) and against
    an in-process app in tests (`backend/tests/test_production_smoke_contract.py`
    passes a real `TestClient` instance directly)."""

    def __init__(self, base_url: str, *, timeout: float = 10.0) -> None:
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout

    def get(self, path: str, *, headers: dict | None = None) -> Response:
        return self._request("GET", path, headers=headers)

    def post(
        self, path: str, *, json: dict | None = None, headers: dict | None = None
    ) -> Response:
        return self._request("POST", path, headers=headers, json_body=json)

    def _request(
        self,
        method: str,
        path: str,
        *,
        headers: dict | None = None,
        json_body: dict | None = None,
    ) -> Response:
        url = f"{self.base_url}{path}"
        request_headers = dict(headers or {})
        data = None
        if json_body is not None:
            data = _dumps(json_body)
            request_headers["Content-Type"] = "application/json"
        request = urllib.request.Request(
            url, data=data, headers=request_headers, method=method
        )
        try:
            with _NO_REDIRECT_OPENER.open(request, timeout=self.timeout) as resp:
                return Response(resp.status, resp.read())
        except urllib.error.HTTPError as error:
            return Response(error.code, error.read())
        except (urllib.error.URLError, OSError, TimeoutError) as error:
            raise _HttpError(str(error)) from error


def _traffic_gate_reason(resp: Response) -> str | None:
    """If `resp` is the ADR 0449 D1 traffic-gate 503 shape, return a
    dedicated reason string; otherwise None (let the caller report a plain
    "unexpected status" instead)."""
    if resp.status_code != 503:
        return None
    try:
        body = resp.json()
    except (ValueError, UnicodeDecodeError):
        return None
    if isinstance(body, dict) and body.get("status") == "not_ready":
        return f"traffic gate active (not_ready): {body.get('reason', '<no reason>')}"
    return None


# ---------------------------------------------------------------------------
# Individual checks
# ---------------------------------------------------------------------------


def check_readiness(client) -> CheckResult:
    try:
        resp = client.get("/health/ready")
    except _HttpError as error:
        return CheckResult("readiness", False, f"request failed: {error}")

    if resp.status_code == 200:
        try:
            body = resp.json()
        except (ValueError, UnicodeDecodeError):
            return CheckResult("readiness", False, "HTTP 200 but body is not valid JSON")
        if body.get("status") == "ready":
            return CheckResult("readiness", True, "ready")
        return CheckResult("readiness", False, f"HTTP 200 but unexpected body: {body!r}")

    if resp.status_code == 503:
        reason = _traffic_gate_reason(resp)
        if reason is not None:
            return CheckResult("readiness", False, reason)
        return CheckResult("readiness", False, "HTTP 503 but not the expected not_ready shape")

    return CheckResult("readiness", False, f"unexpected status {resp.status_code}")


def check_auth(
    client, *, email: str, password: str
) -> tuple[CheckResult, CheckResult, str | None]:
    try:
        resp = client.post("/auth/login", json={"email": email, "password": password})
    except _HttpError as error:
        return (
            CheckResult("auth_login", False, f"request failed: {error}"),
            CheckResult("auth_me", False, "skipped: auth_login failed"),
            None,
        )

    reason = _traffic_gate_reason(resp)
    if reason is not None:
        return (
            CheckResult("auth_login", False, reason),
            CheckResult("auth_me", False, "skipped: auth_login failed"),
            None,
        )
    if resp.status_code != 200:
        return (
            CheckResult("auth_login", False, f"unexpected status {resp.status_code}"),
            CheckResult("auth_me", False, "skipped: auth_login failed"),
            None,
        )
    try:
        body = resp.json()
    except (ValueError, UnicodeDecodeError):
        return (
            CheckResult("auth_login", False, "HTTP 200 but body is not valid JSON"),
            CheckResult("auth_me", False, "skipped: auth_login failed"),
            None,
        )
    token = body.get("access_token") if isinstance(body, dict) else None
    if not token:
        return (
            CheckResult("auth_login", False, "HTTP 200 but no access_token in body"),
            CheckResult("auth_me", False, "skipped: auth_login failed"),
            None,
        )

    login_result = CheckResult("auth_login", True, "ok")
    auth_headers = {"Authorization": f"Bearer {token}"}

    try:
        me_resp = client.get("/auth/me", headers=auth_headers)
    except _HttpError as error:
        return login_result, CheckResult("auth_me", False, f"request failed: {error}"), None

    me_reason = _traffic_gate_reason(me_resp)
    if me_reason is not None:
        return login_result, CheckResult("auth_me", False, me_reason), None
    if me_resp.status_code != 200:
        return (
            login_result,
            CheckResult("auth_me", False, f"unexpected status {me_resp.status_code}"),
            None,
        )
    return login_result, CheckResult("auth_me", True, "ok"), token


def check_settings(client, *, token: str) -> CheckResult:
    try:
        resp = client.get("/settings", headers={"Authorization": f"Bearer {token}"})
    except _HttpError as error:
        return CheckResult("settings", False, f"request failed: {error}")
    reason = _traffic_gate_reason(resp)
    if reason is not None:
        return CheckResult("settings", False, reason)
    if resp.status_code != 200:
        return CheckResult("settings", False, f"unexpected status {resp.status_code}")
    return CheckResult("settings", True, "ok")


def check_community_feed(client, *, token: str) -> CheckResult:
    try:
        resp = client.get("/community/feed", headers={"Authorization": f"Bearer {token}"})
    except _HttpError as error:
        return CheckResult("community_feed", False, f"request failed: {error}")
    reason = _traffic_gate_reason(resp)
    if reason is not None:
        return CheckResult("community_feed", False, reason)
    if resp.status_code == 200:
        return CheckResult("community_feed", True, "reachable and correctly gated (status 200)")
    if resp.status_code == 404:
        # A 404 here is a legitimate outcome either way — a fresh smoke
        # account with no community profile onboarding 404s (see feed.py's
        # own docstring), AND the router being entirely un-mounted (as it is
        # on the tree this round shipped against) also 404s. The two are
        # indistinguishable from a status code alone (round brief MINOR-2),
        # so the detail says exactly that instead of claiming "reachable".
        return CheckResult(
            "community_feed",
            True,
            "404 — either not registered on this deploy, or registered and "
            "correctly gated for this account; a status code alone cannot "
            "tell the two apart, so no reachability is claimed here",
        )
    return CheckResult("community_feed", False, f"unexpected status {resp.status_code}")


def check_lab_routes_absent(client) -> CheckResult:
    failures: list[str] = []
    for method, path in _LAB_ROUTES:
        try:
            resp = client.get(path) if method == "GET" else client.post(path, json={})
        except _HttpError as error:
            failures.append(f"{method} {path}: request failed: {error}")
            continue
        if resp.status_code != 404:
            failures.append(f"{method} {path}: expected 404, got {resp.status_code}")
    if failures:
        return CheckResult("lab_routes_absent", False, "; ".join(failures))
    return CheckResult(
        "lab_routes_absent",
        True,
        "all Lab routes 404 (POST /diagnostics, GET /diagnostics/health, "
        "GET /download) and POST /download is not a registered route "
        "(405 would mean it is)",
    )


def _normalize_fingerprint(value: str) -> str:
    return value.strip().upper().replace("-", ":").replace(" ", "")


def check_fingerprint(signing_certificate: Path, expected_fingerprint: str) -> CheckResult:
    try:
        text = signing_certificate.read_text(encoding="utf-8")
    except OSError as error:
        return CheckResult(
            "fingerprint",
            False,
            f"signing certificate not found or unreadable: {signing_certificate} ({error})",
        )
    try:
        data = json.loads(text)
    except json.JSONDecodeError as error:
        return CheckResult(
            "fingerprint", False, f"signing certificate is not valid JSON: {error}"
        )
    if not isinstance(data, dict) or "sha256Fingerprint" not in data:
        # Fail-closed (§0.0.1 P2 / round brief §5): a missing key is a
        # FAILURE, never a 0-exit pass.
        return CheckResult(
            "fingerprint",
            False,
            f'signing certificate {signing_certificate} is missing the "sha256Fingerprint" key',
        )
    actual = data["sha256Fingerprint"]
    if not isinstance(actual, str) or not actual.strip():
        return CheckResult(
            "fingerprint", False, '"sha256Fingerprint" is empty or not a string'
        )
    if _normalize_fingerprint(actual) != _normalize_fingerprint(expected_fingerprint):
        return CheckResult(
            "fingerprint",
            False,
            f"fingerprint mismatch: --expected-fingerprint={expected_fingerprint!r}, "
            f"sidecar sha256Fingerprint={actual!r}",
        )
    return CheckResult("fingerprint", True, "sidecar sha256Fingerprint matches --expected-fingerprint")


def check_model_manifest(asset_root: Path) -> CheckResult:
    manifest_path = asset_root / "assets" / "ml" / "model_manifest.json"
    try:
        text = manifest_path.read_text(encoding="utf-8")
    except OSError as error:
        return CheckResult(
            "model_manifest", False, f"model manifest artifact not found: {manifest_path} ({error})"
        )
    try:
        json.loads(text)
    except json.JSONDecodeError as error:
        return CheckResult(
            "model_manifest", False, f"model manifest is not valid JSON: {error}"
        )
    return CheckResult("model_manifest", True, f"{manifest_path} present and parses as JSON")


def run_checks(
    client,
    *,
    email: str,
    password: str,
    signing_certificate: Path,
    expected_fingerprint: str,
    asset_root: Path,
) -> list[CheckResult]:
    """Runs every check independently against `client` (a real
    `UrllibClient` or, in tests, an in-process `TestClient`) and the local
    artifact paths. No check is skipped because an earlier one failed,
    except `auth_me`/`settings`/`community_feed`, which need the bearer
    token `auth_login` produces."""
    results: list[CheckResult] = [check_readiness(client)]

    login_result, me_result, token = check_auth(client, email=email, password=password)
    results.append(login_result)
    results.append(me_result)

    if token is not None:
        results.append(check_settings(client, token=token))
        results.append(check_community_feed(client, token=token))
    else:
        results.append(
            CheckResult("settings", False, "skipped: no auth token (see auth_login/auth_me above)")
        )
        results.append(
            CheckResult(
                "community_feed", False, "skipped: no auth token (see auth_login/auth_me above)"
            )
        )

    results.append(check_lab_routes_absent(client))
    results.append(check_fingerprint(signing_certificate, expected_fingerprint))
    results.append(check_model_manifest(asset_root))
    return results


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--base-url", required=True, help="e.g. https://api.strumsight.app")
    parser.add_argument("--email", required=True, help="smoke-test account email (not secret)")
    parser.add_argument(
        "--password-env",
        default=DEFAULT_PASSWORD_ENV,
        help=(
            "Name of the environment variable holding the smoke-test account "
            f"password (default: {DEFAULT_PASSWORD_ENV}). The password is "
            "NEVER accepted as a CLI argument (round brief §5.1)."
        ),
    )
    parser.add_argument(
        "--signing-certificate",
        required=True,
        type=Path,
        help="Path to the dist/signing-certificate.json sidecar (§0.0.1 P2).",
    )
    parser.add_argument(
        "--expected-fingerprint",
        required=True,
        help="Expected SHA-256 certificate fingerprint to compare against the sidecar.",
    )
    parser.add_argument(
        "--asset-root",
        type=Path,
        default=Path("."),
        help="Repo-relative root containing assets/ml/model_manifest.json (§0.0.1 P4).",
    )
    parser.add_argument("--timeout", type=float, default=10.0, help="HTTP timeout in seconds.")
    parser.add_argument(
        "--allow-insecure-http",
        action="store_true",
        help=(
            "Allow a plain http:// --base-url (round brief MAJOR-3). Without "
            "this flag a non-https --base-url is a usage error (exit 2) — a "
            "production/staging target MUST be https:// so the smoke-test "
            "password and the bearer token it obtains are never sent "
            "unencrypted on the wire. Use only for a local/staging run "
            "against a target you know is plain HTTP."
        ),
    )
    return parser


def _https_scheme_error(base_url: str, *, allow_insecure_http: bool) -> str | None:
    """Fail-closed scheme check (round brief MAJOR-3): returns an error
    message if `base_url` is not an acceptable target, `None` if it is.
    `https` is always accepted; plain `http` is accepted only with
    `--allow-insecure-http`. Any other/missing scheme is always rejected."""
    scheme = urlsplit(base_url).scheme
    if scheme == "https":
        return None
    if scheme == "http" and allow_insecure_http:
        return None
    return (
        f"production_smoke: --base-url {base_url!r} must use https:// "
        f"(got scheme {scheme or '<none>'!r}) — a plain http:// target "
        "sends the smoke-test password and the bearer token it obtains "
        "unencrypted on the wire (round brief MAJOR-3). Pass "
        "--allow-insecure-http only for a local/staging run where that is "
        "expected."
    )


def main(argv: list[str]) -> int:
    parser = _build_parser()
    args = parser.parse_args(argv)

    password = os.environ.get(args.password_env)
    if not password:
        print(
            f"production_smoke: environment variable {args.password_env!r} "
            "(--password-env) is not set or empty — the smoke package never "
            "accepts a credential as a CLI argument (round brief §5.1)",
            file=sys.stderr,
        )
        return 2

    scheme_error = _https_scheme_error(
        args.base_url, allow_insecure_http=args.allow_insecure_http
    )
    if scheme_error is not None:
        print(scheme_error, file=sys.stderr)
        return 2

    client = UrllibClient(args.base_url, timeout=args.timeout)
    results = run_checks(
        client,
        email=args.email,
        password=password,
        signing_certificate=args.signing_certificate,
        expected_fingerprint=args.expected_fingerprint,
        asset_root=args.asset_root,
    )

    all_ok = True
    for result in results:
        status = "PASS" if result.ok else "FAIL"
        print(f"[{status}] {result.name}: {result.detail}")
        if not result.ok:
            all_ok = False

    if all_ok:
        print(f"production_smoke: ok — {len(results)} check(s) passed against {args.base_url}")
        return 0
    print("production_smoke: one or more checks failed", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
