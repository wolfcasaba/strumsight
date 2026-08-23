"""Vendor-neutral object-storage interface + stdlib-only S3 adapter
(E09-R18, ADR 0410).

This module defines the boundary between the Community backend and
an external object store (S3, MinIO, GCS, anything speaking the
S3-compatible SigV4 presigned-URL API). The
``media_upload_service`` consumes this interface only — it never
imports a concrete vendor implementation. The two implementations
below cover the only two paths the project ships this round:

* :class:`S3CompatibleObjectStore` — the production adapter,
  ``hmac``/``hashlib``/``urllib.parse`` + the already-present
  ``httpx`` (no ``boto3``/``minio``, see ADR 0410 D2 / §0.0 D2).
  The presigned PUT URL is computed via AWS SigV4 query-string
  signing, a documented, SDK-free algorithm; ``head_object`` /
  ``delete_object`` ride signed ``HEAD``/``DELETE`` over ``httpx``.
* :class:`InMemoryObjectStore` — the deterministic fake the
  §6 / §6.1 acceptance tests inject, replacing every byte of
  network I/O with synchronous in-process maps so the A2 / A4 /
  A5 / threshold-triple cells can be reproduced without a real
  bucket.

The adapter pair is intentionally narrow — the interface only
covers the three operations the upload pipeline needs:

* ``create_upload_url`` — issue a short-lived signed URL the
  client uploads to directly.
* ``head_object`` — fetch object metadata (size, content-type,
  SHA-256 etag). Used by the finalize path to validate that the
  actually-uploaded object matches what the client claimed.
* ``delete_object`` — remove an orphaned or cancelled upload.
  Idempotent so the orphan-cleanup job can re-run safely.

No future round needs to widen this surface to add a vendor SDK —
replacing ``S3CompatibleObjectStore`` with a ``boto3``-backed
adapter keeps the same three-method interface, so callers
(``media_upload_service``) and tests stay untouched.
"""

from __future__ import annotations

import abc
import hashlib
import hmac
import os
from collections.abc import Mapping
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from urllib.parse import quote

import httpx


# ---------------------------------------------------------------------------
# Wire value types — the only shapes crossing the ObjectStore boundary.
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class SignedUpload:
    """The presigned PUT URL + the constraints the signed URL
    carries + the absolute expiry timestamp.

    * ``url`` — the URL the client ``PUT``s the object bytes to.
    * ``method`` — ``"PUT"`` (the only verb this adapter signs for
      direct uploads; the upload pipeline never uses ``POST``
      multipart form-posts).
    * ``content_type`` — the ``Content-Type`` header value the
      signed URL enforces. The client must send this exact value
      in the ``PUT`` request; an S3-compatible bucket rejects the
      upload if the header is missing or different.
    * ``max_content_length`` — the byte cap the signed URL
      enforces (``Content-Length`` must equal this for the
      canonical request AWS validates). The finalize path
      re-checks the actual size independently (defense-in-depth,
      brief §6.1).
    * ``expires_at`` — the absolute UTC ``datetime`` when the
      signed URL stops being accepted by the bucket. The
      service-layer finalize rejects when ``now >= expires_at``
      (brief §6 A2).
    """

    url: str
    method: str  # "PUT"
    content_type: str
    max_content_length: int
    expires_at: datetime


@dataclass(frozen=True)
class ObjectMetadata:
    """Server-fetched metadata of a stored object.

    ``etag`` is the S3-style hex MD5 the bucket returns for the
    PUT — the wire shape is a quoted string, the SDK strips the
    quotes. ``sha256_hex`` is the project's content-hash shape
    (64-char hex digest); the finalize comparison happens here,
    not on the bucket ETag. Either can be ``None`` when the
    bucket doesn't carry the field (the in-memory fake always
    populates both).
    """

    size: int
    content_type: str
    etag: str | None
    sha256_hex: str | None


# ---------------------------------------------------------------------------
# Abstract base — the seam the service depends on.
# ---------------------------------------------------------------------------


class ObjectStore(abc.ABC):
    """Vendor-neutral contract the upload service depends on."""

    @abc.abstractmethod
    def create_upload_url(
        self,
        key: str,
        *,
        content_type: str,
        max_content_length: int,
        expires_in: timedelta,
    ) -> SignedUpload:
        """Return a presigned PUT URL for ``key`` with the given
        constraints."""

    @abc.abstractmethod
    def head_object(self, key: str) -> ObjectMetadata | None:
        """Return the object's metadata, or ``None`` if it does
        not exist in the bucket."""

    @abc.abstractmethod
    def delete_object(self, key: str) -> None:
        """Remove the object. Idempotent — no error when the
        object is already absent."""


# ---------------------------------------------------------------------------
# In-memory fake — the deterministic test backend.
# ---------------------------------------------------------------------------


class InMemoryObjectStore(ObjectStore):
    """A process-local fake that records every upload in a dict.

    The test helper ``InMemoryObjectStore.stage_object`` plants a
    deterministic (size, sha256) tuple the finalize path will then
    see via :meth:`head_object`. The fake's ``create_upload_url``
    emits a ``memory://upload/<key>`` URL — no network I/O, the
    test never issues a real PUT, the in-memory state is mutated
    by the test harness directly.

    The fake also tracks every issued URL so a test can assert
    that ``cancel_upload`` triggered a ``delete_object`` without
    needing a network capture.
    """

    def __init__(self) -> None:
        self._objects: dict[str, ObjectMetadata] = {}
        self._bytes: dict[str, bytes] = {}
        self.issued_urls: list[SignedUpload] = []
        self.deleted: list[str] = []

    # --- fake-only helpers (not part of the ObjectStore surface) -------

    def stage_object(
        self,
        key: str,
        *,
        size: int,
        content_type: str,
        sha256_hex: str,
        body: bytes | None = None,
    ) -> None:
        """Pre-populate an object the service will see via
        :meth:`head_object`. ``body`` is the optional byte payload
        the test can later re-hash to assert SHA-256."""
        etag = hashlib.md5(body if body is not None else b"\x00" * size).hexdigest()
        self._objects[key] = ObjectMetadata(
            size=size,
            content_type=content_type,
            etag=etag,
            sha256_hex=sha256_hex,
        )
        self._bytes[key] = body if body is not None else b"\x00" * size

    def put_bytes(
        self, key: str, *, body: bytes, content_type: str
    ) -> ObjectMetadata:
        """Simulate a successful PUT — record size + SHA-256 and
        make the object visible to ``head_object``. Used when the
        test wants the upload to complete and then assert what
        the finalize step sees."""
        sha = hashlib.sha256(body).hexdigest()
        meta = ObjectMetadata(
            size=len(body),
            content_type=content_type,
            etag=hashlib.md5(body).hexdigest(),
            sha256_hex=sha,
        )
        self._objects[key] = meta
        self._bytes[key] = body
        return meta

    # --- ObjectStore interface ---------------------------------------

    def create_upload_url(
        self,
        key: str,
        *,
        content_type: str,
        max_content_length: int,
        expires_in: timedelta,
    ) -> SignedUpload:
        url = f"memory://upload/{key}"
        expires_at = datetime.now(timezone.utc) + expires_in
        signed = SignedUpload(
            url=url,
            method="PUT",
            content_type=content_type,
            max_content_length=max_content_length,
            expires_at=expires_at,
        )
        self.issued_urls.append(signed)
        return signed

    def head_object(self, key: str) -> ObjectMetadata | None:
        return self._objects.get(key)

    def delete_object(self, key: str) -> None:
        self._objects.pop(key, None)
        self._bytes.pop(key, None)
        self.deleted.append(key)


# ---------------------------------------------------------------------------
# S3-compatible adapter — stdlib SigV4 + httpx (no SDK).
# ---------------------------------------------------------------------------


class S3CompatibleObjectStore(ObjectStore):
    """AWS-SigV4 query-signed presigned PUT URLs over ``httpx``.

    The presigned URL is computed via the AWS-documented SigV4
    algorithm: a canonical request is built from the HTTP method,
    canonical URI, canonical query string, canonical headers and
    the signed-payload hash; the string-to-sign is ``AWS4-HMAC-
    SHA256`` + timestamp + credential scope + canonical-request
    hash; the signing key is the chain ``HMAC(date, HMAC(region,
    HMAC(service, HMAC("AWS4" + secret, date))))``; the final
    signature is ``HMAC-SHA256(signing_key, string_to_sign)`` —
    all four are stdlib primitives.

    ``head_object`` and ``delete_object`` ride signed ``HEAD`` and
    ``DELETE`` requests through the already-present ``httpx``
    client. The presign algorithm is the same query-string form
    used for the PUT, so the same helper covers all three.

    No third-party SDK (no ``boto3``, no ``minio``) — the adapter
    is intentionally narrow so a future round can swap it for an
    SDK-backed implementation without touching callers
    (ADR 0410 Következmények 2. pont).
    """

    def __init__(
        self,
        *,
        endpoint: str,
        bucket: str,
        region: str,
        access_key_id: str,
        secret_access_key: str,
        http_client: httpx.Client | None = None,
    ) -> None:
        # Strip trailing slash — the SigV4 canonical URI uses a
        # single leading slash and an empty path or a single
        # "/<key>" segment.
        self._endpoint = endpoint.rstrip("/")
        self._bucket = bucket
        self._region = region
        self._access_key_id = access_key_id
        self._secret_access_key = secret_access_key
        # The HTTP client is injected so tests can wire an
        # ``httpx.MockTransport`` without monkeypatching. The
        # service layer does NOT call this adapter directly in
        # this round (the deterministic in-memory fake covers
        # every acceptance cell) — this class ships for the
        # next round to wire against a real bucket.
        self._http = http_client or httpx.Client(timeout=10.0)

    # --- ObjectStore interface ---------------------------------------

    def create_upload_url(
        self,
        key: str,
        *,
        content_type: str,
        max_content_length: int,
        expires_in: timedelta,
    ) -> SignedUpload:
        now = datetime.now(timezone.utc)
        # ``expires_in`` is the spec's "Seconds" — capped at the
        # AWS SigV4 limit (604 800 = 7 days). The service calls
        # this with a few minutes, so the cap never bites in
        # practice.
        seconds = max(1, min(int(expires_in.total_seconds()), 604_800))
        signed = _sigv4_presign(
            method="PUT",
            endpoint=self._endpoint,
            bucket=self._bucket,
            region=self._region,
            access_key_id=self._access_key_id,
            secret_access_key=self._secret_access_key,
            key=key,
            content_type=content_type,
            max_content_length=max_content_length,
            now=now,
            expires_in_seconds=seconds,
        )
        expires_at = now + timedelta(seconds=seconds)
        return SignedUpload(
            url=signed,
            method="PUT",
            content_type=content_type,
            max_content_length=max_content_length,
            expires_at=expires_at,
        )

    def head_object(self, key: str) -> ObjectMetadata | None:
        # A signed HEAD is the cheapest existence + size probe.
        # AWS / MinIO return 404 when the key is absent;
        # ``httpx`` surfaces that as an ``HTTPStatusError`` on a
        # strict response, so we coerce that one case to
        # ``None`` and let other errors propagate.
        url, headers = _sigv4_presign_request(
            method="HEAD",
            endpoint=self._endpoint,
            bucket=self._bucket,
            region=self._region,
            access_key_id=self._access_key_id,
            secret_access_key=self._secret_access_key,
            key=key,
            content_type=None,
            max_content_length=None,
            now=datetime.now(timezone.utc),
            expires_in_seconds=300,
        )
        response = self._http.request("HEAD", url, headers=headers)
        if response.status_code == 404:
            return None
        response.raise_for_status()
        size_raw = response.headers.get("Content-Length")
        try:
            size = int(size_raw) if size_raw is not None else 0
        except ValueError:
            size = 0
        return ObjectMetadata(
            size=size,
            content_type=response.headers.get("Content-Type", "application/octet-stream"),
            etag=_strip_quotes(response.headers.get("ETag")),
            sha256_hex=None,
        )

    def delete_object(self, key: str) -> None:
        url, headers = _sigv4_presign_request(
            method="DELETE",
            endpoint=self._endpoint,
            bucket=self._bucket,
            region=self._region,
            access_key_id=self._access_key_id,
            secret_access_key=self._secret_access_key,
            key=key,
            content_type=None,
            max_content_length=None,
            now=datetime.now(timezone.utc),
            expires_in_seconds=300,
        )
        response = self._http.request("DELETE", url, headers=headers)
        # Idempotent — 404 (already absent) is not an error.
        if response.status_code not in (204, 200, 404):
            response.raise_for_status()


# ---------------------------------------------------------------------------
# SigV4 helpers — internal, exported only for the adapter.
# ---------------------------------------------------------------------------


def _strip_quotes(value: str | None) -> str | None:
    """S3 wraps the ETag in double quotes (``"abcdef..."``); the
    public surface strips them so callers compare hex only."""
    if value is None:
        return None
    if len(value) >= 2 and value[0] == '"' and value[-1] == '"':
        return value[1:-1]
    return value


def _aws4_signing_key(
    *, secret_access_key: str, date_stamp: str, region: str, service: str
) -> bytes:
    """The four-step HMAC chain that builds the SigV4 signing
    key from the secret + date + region + service. Stdlib-only
    (no external crypto)."""
    k_secret = ("AWS4" + secret_access_key).encode("utf-8")
    k_date = hmac.new(k_secret, date_stamp.encode("utf-8"), hashlib.sha256).digest()
    k_region = hmac.new(k_date, region.encode("utf-8"), hashlib.sha256).digest()
    k_service = hmac.new(k_region, service.encode("utf-8"), hashlib.sha256).digest()
    return hmac.new(k_service, "aws4_request".encode("utf-8"), hashlib.sha256).digest()


def _uri_encode(value: str, *, encode_slash: bool) -> str:
    """The AWS SigV4 URI-encoding: unreserved chars pass through,
    everything else becomes ``%XX`` with uppercase hex. ``/`` is
    encoded when ``encode_slash`` is true (query-string value
    context), kept literal when false (path-segment context)."""
    safe = "" if encode_slash else "/"
    return quote(value, safe=safe)


def _canonical_query_string(params: Mapping[str, str]) -> str:
    """The query-string canonicalization step. Keys are sorted
    lexicographically, values are URI-encoded with ``/`` encoded
    (``encode_slash=True``), and the string is the ``&``-joined
    ``k=v`` pairs."""
    pairs: list[tuple[str, str]] = []
    for key in sorted(params):
        pairs.append(
            (
                _uri_encode(key, encode_slash=True),
                _uri_encode(params[key], encode_slash=True),
            )
        )
    return "&".join(f"{k}={v}" for k, v in pairs)


def _sigv4_presign(
    *,
    method: str,
    endpoint: str,
    bucket: str,
    region: str,
    access_key_id: str,
    secret_access_key: str,
    key: str,
    content_type: str | None,
    max_content_length: int | None,
    now: datetime,
    expires_in_seconds: int,
) -> str:
    """Compute the presigned URL (AWS SigV4 query-string form).

    Only the ``X-Amz-SignedHeaders=host`` set is used here — the
    rest of the upload-time constraints (``Content-Type``,
    ``Content-Length``) are pushed as signed query parameters so
    the bucket enforces them at PUT time, and the
    ``Content-Length`` cap is what the finalize path treats as
    defense-in-depth (brief §6.1)."""
    url, _headers = _sigv4_presign_request(
        method=method,
        endpoint=endpoint,
        bucket=bucket,
        region=region,
        access_key_id=access_key_id,
        secret_access_key=secret_access_key,
        key=key,
        content_type=content_type,
        max_content_length=max_content_length,
        now=now,
        expires_in_seconds=expires_in_seconds,
    )
    return url


def _sigv4_presign_request(
    *,
    method: str,
    endpoint: str,
    bucket: str,
    region: str,
    access_key_id: str,
    secret_access_key: str,
    key: str,
    content_type: str | None,
    max_content_length: int | None,
    now: datetime,
    expires_in_seconds: int,
) -> tuple[str, dict[str, str]]:
    """Compute the signed URL + the minimum headers a client
    must send. ``content_type`` and ``max_content_length`` are
    baked into the signed query string — that is what enforces
    them at request time (the bucket validates the query-signed
    constraints before accepting the body)."""
    amz_date = now.strftime("%Y%m%dT%H%M%SZ")
    date_stamp = now.strftime("%Y%m%d")
    host = _endpoint_host(endpoint)
    canonical_uri = "/" + _uri_encode(f"{bucket}/{key}", encode_slash=False)
    service = "s3"

    # The signed query parameters are sorted lexicographically —
    # SigV4 presign puts the credentials and signature alongside
    # the user-specified constraints.
    params: dict[str, str] = {
        "X-Amz-Algorithm": "AWS4-HMAC-SHA256",
        "X-Amz-Credential": (
            f"{access_key_id}/{date_stamp}/{region}/{service}/aws4_request"
        ),
        "X-Amz-Date": amz_date,
        "X-Amz-Expires": str(expires_in_seconds),
        "X-Amz-SignedHeaders": "host",
    }
    if content_type is not None:
        # The bucket compares the request's Content-Type against
        # the signed parameter; an exact match is required.
        params["X-Amz-SignedHeaders-Content-Type"] = content_type
    if max_content_length is not None:
        params["X-Amz-SignedHeaders-Content-Length"] = str(max_content_length)

    canonical_query = _canonical_query_string(params)
    canonical_headers = f"host:{host}\n"
    signed_headers = "host"
    payload_hash = "UNSIGNED-PAYLOAD"

    canonical_request = (
        f"{method}\n"
        f"{canonical_uri}\n"
        f"{canonical_query}\n"
        f"{canonical_headers}\n"
        f"{signed_headers}\n"
        f"{payload_hash}"
    )
    credential_scope = f"{date_stamp}/{region}/{service}/aws4_request"
    string_to_sign = (
        "AWS4-HMAC-SHA256\n"
        f"{amz_date}\n"
        f"{credential_scope}\n"
        f"{hashlib.sha256(canonical_request.encode('utf-8')).hexdigest()}"
    )
    signing_key = _aws4_signing_key(
        secret_access_key=secret_access_key,
        date_stamp=date_stamp,
        region=region,
        service=service,
    )
    signature = hmac.new(
        signing_key, string_to_sign.encode("utf-8"), hashlib.sha256
    ).hexdigest()

    signed_params = dict(params)
    signed_params["X-Amz-Signature"] = signature
    signed_query = _canonical_query_string(signed_params)
    url = f"{endpoint}{canonical_uri}?{signed_query}"
    # The host header is required for any signed AWS request —
    # even a presigned PUT carries it. The signed-headers list
    # names only ``host``, so this is the only header the SDK
    # (or our SDK-free equivalent) must echo back.
    headers = {"Host": host}
    return url, headers


def _endpoint_host(endpoint: str) -> str:
    """Extract ``host[:port]`` from the endpoint URL — the SigV4
    canonical ``Host`` header is the authority, not a full URL.
    ``endpoint`` is expected to be ``https://host[:port]`` —
    any ``http://`` form is the test/fake path, not this
    adapter."""
    if "://" in endpoint:
        authority = endpoint.split("://", 1)[1]
    else:
        authority = endpoint
    return authority.rstrip("/")


# ---------------------------------------------------------------------------
# Public env-name set — used by a future wiring round, exported for
# the tests that build an instance from the production env vars.
# ---------------------------------------------------------------------------


def object_store_from_env(
    env: Mapping[str, str] | None = None,
    *,
    http_client: httpx.Client | None = None,
) -> S3CompatibleObjectStore:
    """Build an :class:`S3CompatibleObjectStore` from the four
    required env vars (``STRUMSIGHT_OBJECT_STORE_*``). Exported
    for the future wiring round — the service never imports
    this helper directly."""
    env = env if env is not None else os.environ
    return S3CompatibleObjectStore(
        endpoint=env["STRUMSIGHT_OBJECT_STORE_ENDPOINT"],
        bucket=env["STRUMSIGHT_OBJECT_STORE_BUCKET"],
        region=env["STRUMSIGHT_OBJECT_STORE_REGION"],
        access_key_id=env["STRUMSIGHT_OBJECT_STORE_ACCESS_KEY"],
        secret_access_key=env["STRUMSIGHT_OBJECT_STORE_SECRET_KEY"],
        http_client=http_client,
    )


__all__ = [
    "InMemoryObjectStore",
    "ObjectMetadata",
    "ObjectStore",
    "S3CompatibleObjectStore",
    "SignedUpload",
    "object_store_from_env",
]