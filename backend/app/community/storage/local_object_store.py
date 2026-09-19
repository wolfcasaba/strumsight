"""Filesystem-backed :class:`ObjectStore` for the server-received upload
path (WP-H5).

The E09-R18 pipeline was designed around presigned direct-to-bucket
uploads: the client PUTs the bytes straight to S3 and the server only
ever sees metadata. That design cannot sniff magic bytes and cannot
strip EXIF — the bytes never pass through the server — so the
``POST /community/media`` endpoint this round ships takes the bytes
server-side instead (see ``docs/security/community-threat-model.md``
§"Why server-received, not presigned").

To do that without forking the upload service, this adapter implements
the SAME :class:`ObjectStore` contract against a local directory and
adds one method the presigned adapters cannot have — :meth:`put_object`,
"the server writes the bytes itself". ``media_upload_service`` is then
reused verbatim: ``create_upload_intent`` → :meth:`put_object` →
``finalize_upload``, with the finalize step's ``head_object`` re-check
seeing exactly the bytes that were written.

Layout and safety:

* One file per object, at ``<root>/<object_key>``. The key is derived
  server-side by ``media_upload_service._derive_object_key`` from the
  profile id + a v4 UUID, so it is never attacker-controlled — but
  :meth:`_resolve` still rejects any key that escapes ``root`` after
  normalization (defense in depth against a future caller that does
  pass a key through).
* A ``.meta`` sidecar carries the recorded content type and SHA-256, so
  :meth:`head_object` answers from stored state rather than re-sniffing.
* Writes are atomic: bytes land in a ``.tmp`` file that is then
  ``os.replace``d, so a crashed request never leaves a half-object that
  a later ``head_object`` would treat as complete.
* Files are created with mode ``0o600`` and directories ``0o700`` — the
  media root holds user-uploaded content and must not be world-readable
  on a shared host.
"""

from __future__ import annotations

import hashlib
import json
import os
from collections.abc import Iterator
from datetime import datetime, timedelta, timezone
from pathlib import Path

from .object_store import ObjectMetadata, ObjectStore, SignedUpload

#: Chunk size for the streamed read path. 64 KiB keeps a large audio
#: download off the "one giant bytes object in RAM" path.
STREAM_CHUNK_BYTES: int = 64 * 1024


class LocalObjectStore(ObjectStore):
    """An :class:`ObjectStore` backed by a directory on the app host."""

    def __init__(self, root: str | os.PathLike[str]) -> None:
        self._root = Path(root).resolve()
        self._root.mkdir(parents=True, exist_ok=True, mode=0o700)

    @property
    def root(self) -> Path:
        return self._root

    # --- path safety --------------------------------------------------

    def _resolve(self, key: str) -> Path:
        """Map ``key`` to an absolute path INSIDE the root, or raise.

        ``Path.resolve`` collapses ``..`` segments; comparing the result
        against the root is what makes a traversal attempt fail closed.
        """
        if not key or key.startswith("/") or "\x00" in key:
            raise ValueError(f"invalid object key: {key!r}")
        candidate = (self._root / key).resolve()
        if candidate != self._root and self._root not in candidate.parents:
            raise ValueError(f"object key escapes storage root: {key!r}")
        return candidate

    @staticmethod
    def _meta_path(path: Path) -> Path:
        return path.with_name(path.name + ".meta")

    # --- ObjectStore interface ---------------------------------------

    def create_upload_url(
        self,
        key: str,
        *,
        content_type: str,
        max_content_length: int,
        expires_in: timedelta,
    ) -> SignedUpload:
        """Return a non-network "upload target" descriptor.

        There is no URL for the client to PUT to in the server-received
        design — the bytes arrive in the same request that creates the
        intent. The descriptor is still produced because
        ``create_upload_intent`` persists its ``expires_at`` onto the
        row and ``finalize_upload`` compares against it; the ``url`` is
        an opaque ``local://`` marker that is never returned to a
        client (the router's response schema has no URL field).
        """
        return SignedUpload(
            url=f"local://{key}",
            method="PUT",
            content_type=content_type,
            max_content_length=max_content_length,
            expires_at=datetime.now(timezone.utc) + expires_in,
        )

    def head_object(self, key: str) -> ObjectMetadata | None:
        path = self._resolve(key)
        meta_path = self._meta_path(path)
        if not path.is_file() or not meta_path.is_file():
            return None
        try:
            recorded = json.loads(meta_path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return None
        return ObjectMetadata(
            size=path.stat().st_size,
            content_type=str(recorded.get("content_type", "application/octet-stream")),
            etag=recorded.get("sha256_hex"),
            sha256_hex=recorded.get("sha256_hex"),
        )

    def delete_object(self, key: str) -> None:
        path = self._resolve(key)
        for target in (path, self._meta_path(path)):
            try:
                target.unlink()
            except FileNotFoundError:
                pass

    # --- server-received extension -----------------------------------

    def put_object(self, key: str, *, body: bytes, content_type: str) -> ObjectMetadata:
        """Write ``body`` under ``key`` and return its metadata.

        This is the method a presigned adapter cannot offer, and the
        reason the server-received path uses this store: the bytes are
        in the server's hands, which is what makes sniffing and EXIF
        stripping possible at all.
        """
        path = self._resolve(key)
        path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        digest = hashlib.sha256(body).hexdigest()
        tmp = path.with_name(path.name + ".tmp")
        # 0o600: the media root can sit on a host with other services.
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        try:
            with os.fdopen(fd, "wb") as handle:
                handle.write(body)
                handle.flush()
                os.fsync(handle.fileno())
        except BaseException:
            tmp.unlink(missing_ok=True)
            raise
        os.replace(tmp, path)
        meta_path = self._meta_path(path)
        meta_tmp = meta_path.with_name(meta_path.name + ".tmp")
        meta_fd = os.open(meta_tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(meta_fd, "w", encoding="utf-8") as handle:
            json.dump({"content_type": content_type, "sha256_hex": digest}, handle)
        os.replace(meta_tmp, meta_path)
        return ObjectMetadata(
            size=len(body),
            content_type=content_type,
            etag=digest,
            sha256_hex=digest,
        )

    def open_stream(self, key: str) -> Iterator[bytes]:
        """Yield the object's bytes in :data:`STREAM_CHUNK_BYTES` chunks.

        Raises ``FileNotFoundError`` when the object is absent — the
        router translates that to the same uniform 404 an unauthorized
        read gets, so "gone" and "not yours" stay indistinguishable.
        """
        path = self._resolve(key)
        with path.open("rb") as handle:
            while True:
                chunk = handle.read(STREAM_CHUNK_BYTES)
                if not chunk:
                    return
                yield chunk


__all__ = ["STREAM_CHUNK_BYTES", "LocalObjectStore"]
