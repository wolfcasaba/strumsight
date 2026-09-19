"""Content-addressed filesystem store for re-encoded Community media.

The store holds ONLY post-transcode bytes: the uploader's original file
never reaches the disk (it lives in the request's memory for the length
of the pipeline and is dropped). What is written is therefore always the
output of :mod:`.transcode`.

Layout::

    <media_root>/<sha[0:2]>/<sha[2:4]>/<sha>

``sha`` is the hex SHA-256 of the STORED bytes, so the path is derived
from content, never from caller input. Two consequences worth naming:

* **No traversal surface.** A path is built from a 64-character hex
  digest this module computed itself. There is no code path from a
  request field to a path segment: the router resolves ``public_id →
  row``, and the row carries the digest. :meth:`FileMediaStore.resolve`
  additionally re-validates the digest shape and asserts the resolved
  path stays inside the root, so even a corrupted row cannot escape.
* **Deduplication is free, deletion is refcounted.** Two users uploading
  the same picture converge on one file. :meth:`delete` therefore takes
  the number of OTHER live rows still pointing at the digest and unlinks
  only at zero — deleting your copy must not break someone else's post.
"""

from __future__ import annotations

import hashlib
import os
import re
import tempfile
from pathlib import Path
from typing import Final

_DIGEST_PATTERN: Final[re.Pattern[str]] = re.compile(r"^[0-9a-f]{64}$")


class MediaStoreError(Exception):
    """The store refused an operation (a corrupt digest, a bad root)."""


def sha256_hex(data: bytes) -> str:
    """The lowercase hex SHA-256 of ``data`` — the content address."""
    return hashlib.sha256(data).hexdigest()


class FileMediaStore:
    """Content-addressed store rooted at ``root``.

    The root is created on demand with ``0o700`` so a shared host cannot
    read another service's uploads; files are written ``0o600`` for the
    same reason. Writes are atomic (temp file in the same directory +
    ``os.replace``) so a crash mid-write cannot leave a half file that
    later reads would serve as a valid image.
    """

    def __init__(self, root: str | os.PathLike[str]) -> None:
        self._root = Path(root).resolve()

    @property
    def root(self) -> Path:
        return self._root

    # -- path derivation ------------------------------------------------

    def relative_path(self, digest: str) -> str:
        """``<aa>/<bb>/<digest>`` for a validated digest."""
        if not _DIGEST_PATTERN.match(digest):
            raise MediaStoreError("digest is not a 64-char lowercase hex string")
        return f"{digest[0:2]}/{digest[2:4]}/{digest}"

    def resolve(self, digest: str) -> Path:
        """Absolute path for ``digest``, proven to be inside the root.

        The containment assertion is belt-and-braces: the digest pattern
        above already excludes ``..`` and separators, so this can only
        fire if the pattern is later loosened. Keeping both means a
        future loosening fails loudly instead of silently opening a
        traversal.
        """
        candidate = (self._root / self.relative_path(digest)).resolve()
        try:
            candidate.relative_to(self._root)
        except ValueError as exc:  # pragma: no cover - unreachable today
            raise MediaStoreError("resolved path escapes the media root") from exc
        return candidate

    # -- writes ---------------------------------------------------------

    def put(self, data: bytes) -> tuple[str, Path]:
        """Store ``data`` and return ``(digest, path)``.

        Idempotent: re-storing identical bytes is a no-op that returns
        the existing path.
        """
        digest = sha256_hex(data)
        path = self.resolve(digest)
        path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        if path.exists():
            return digest, path
        fd, tmp_name = tempfile.mkstemp(dir=str(path.parent), prefix=".tmp-")
        tmp_path = Path(tmp_name)
        try:
            with os.fdopen(fd, "wb") as handle:
                handle.write(data)
                handle.flush()
                os.fsync(handle.fileno())
            os.chmod(tmp_path, 0o600)
            os.replace(tmp_path, path)
        except BaseException:
            tmp_path.unlink(missing_ok=True)
            raise
        return digest, path

    # -- reads ----------------------------------------------------------

    def read(self, digest: str) -> bytes:
        """Return the stored bytes, or raise :class:`MediaStoreError`."""
        path = self.resolve(digest)
        try:
            return path.read_bytes()
        except OSError as exc:
            raise MediaStoreError("stored media file is missing") from exc

    def exists(self, digest: str) -> bool:
        try:
            return self.resolve(digest).is_file()
        except MediaStoreError:
            return False

    # -- deletes --------------------------------------------------------

    def delete(self, digest: str, *, other_references: int) -> bool:
        """Unlink the file when nothing else references the digest.

        ``other_references`` is the count of OTHER live rows pointing at
        the same content. A positive count keeps the file and returns
        ``False``; the caller's own row is expected to be excluded from
        the count by the caller.
        """
        if other_references > 0:
            return False
        try:
            path = self.resolve(digest)
        except MediaStoreError:
            return False
        try:
            path.unlink(missing_ok=True)
        except OSError:
            return False
        # Prune the two shard directories when they empty out, so a
        # long-lived deploy does not accumulate 65 536 empty folders.
        for directory in (path.parent, path.parent.parent):
            try:
                directory.rmdir()
            except OSError:
                break
        return True


__all__ = ["FileMediaStore", "MediaStoreError", "sha256_hex"]
