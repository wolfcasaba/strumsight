"""Malware scanning port + adapters (threat model A6.2.5).

Two adapters, and deliberately no third:

* :class:`ClamdScanner` speaks clamd's ``INSTREAM`` protocol over a UNIX
  socket or TCP. Every failure mode — refused connection, timeout, short
  read, unparseable answer — is a REJECT, never an accept.
* :class:`DisabledScanner` REJECTS every upload with
  ``scanner_not_configured``.

There is no ``PassThroughScanner``/``NullScanner``. A "scanner" that
returns clean without looking is worse than no scanner at all: it turns a
missing control into a green checkmark, and every later reader of the row
(the operator, the moderator, the audit) is told the bytes were scanned.
The cost of this choice is explicit and documented: a deployment that
flips ``STRUMSIGHT_COMMUNITY_MEDIA_ENABLED=true`` without standing up
clamd accepts NO uploads at all. That is the intended failure direction
(runbook §7.3).

Protocol notes (clamd ``INSTREAM``)
-----------------------------------

The session is::

    ->  b"zINSTREAM\\0"
    ->  <4-byte big-endian chunk length><chunk bytes>   (repeated)
    ->  b"\\x00\\x00\\x00\\x00"                            (terminator)
    <-  b"stream: OK\\0"            | b"stream: <SIG> FOUND\\0"
                                   | b"INSTREAM size limit exceeded..."

``z``-prefixed commands are NUL-terminated (rather than the ``n`` newline
variant) because the NUL form is what clamd documents as the
non-ambiguous framing. The chunk size stays below clamd's default
``StreamMaxLength`` handling by being small (64 KiB); a payload larger
than clamd's own limit produces the size-limit answer, which this adapter
maps to a reject like every other non-``OK`` outcome.
"""

from __future__ import annotations

import abc
import socket
from dataclasses import dataclass
from typing import Final

#: Rejection code when the operator has not configured a scanner.
REJECT_NOT_CONFIGURED: Final[str] = "scanner_not_configured"
#: Rejection code when the scanner ran and found something.
REJECT_INFECTED: Final[str] = "malware_detected"
#: Rejection code when the scanner could not be reached / answered.
REJECT_UNAVAILABLE: Final[str] = "scanner_unavailable"

_INSTREAM_CHUNK: Final[int] = 64 * 1024
_RESPONSE_LIMIT: Final[int] = 4096


@dataclass(frozen=True)
class ScanVerdict:
    """The outcome of one scan.

    ``clean`` is the ONLY value that lets an upload proceed. ``code`` is
    the machine-readable rejection code persisted on the row when
    ``clean`` is false; ``signature`` carries the scanner's own name for
    the finding (audit only — never echoed to the client, because it is
    attacker-influenced text).
    """

    clean: bool
    code: str | None = None
    signature: str | None = None

    @staticmethod
    def ok() -> "ScanVerdict":
        return ScanVerdict(clean=True)


class MediaScanner(abc.ABC):
    """The port the pipeline consumes. Implementations must fail closed."""

    #: Short adapter name persisted on the row for the audit trail.
    name: str = "scanner"

    @abc.abstractmethod
    def scan(self, data: bytes) -> ScanVerdict:
        """Return a verdict for ``data``. MUST NOT raise."""


class DisabledScanner(MediaScanner):
    """The fail-closed default: every upload is rejected.

    Selected by ``STRUMSIGHT_MEDIA_SCANNER=disabled`` (the default). The
    adapter exists so "no scanner configured" is a REJECT with a named
    code rather than a silent accept.
    """

    name = "disabled"

    def scan(self, data: bytes) -> ScanVerdict:  # noqa: ARG002 - port shape
        return ScanVerdict(clean=False, code=REJECT_NOT_CONFIGURED)


class ClamdScanner(MediaScanner):
    """clamd ``INSTREAM`` adapter over a UNIX socket or TCP.

    ``socket_path`` wins over ``host``/``port`` when non-empty — a local
    daemon over a UNIX socket is the deployment shape the runbook
    recommends, because it needs no network exposure at all.

    Every exception raised by the socket layer is caught and mapped to
    :data:`REJECT_UNAVAILABLE`. The adapter never lets an infrastructure
    failure look like a clean file.
    """

    name = "clamd"

    def __init__(
        self,
        *,
        host: str = "127.0.0.1",
        port: int = 3310,
        socket_path: str = "",
        timeout_seconds: float = 10.0,
    ) -> None:
        self._host = host
        self._port = port
        self._socket_path = socket_path
        self._timeout = timeout_seconds

    # -- socket seam ----------------------------------------------------
    #
    # Split out so the tests can point the adapter at a fake clamd
    # listening on an ephemeral port (or a temp UNIX socket) without
    # monkeypatching the module.

    def _connect(self) -> socket.socket:
        if self._socket_path:
            sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            sock.settimeout(self._timeout)
            sock.connect(self._socket_path)
            return sock
        sock = socket.create_connection(
            (self._host, self._port),
            timeout=self._timeout,
        )
        sock.settimeout(self._timeout)
        return sock

    def scan(self, data: bytes) -> ScanVerdict:
        try:
            raw = self._instream(data)
        except (OSError, socket.timeout):
            # Refused, reset, timed out, DNS-less host, missing socket
            # file — all the same answer: we did not scan, so we do not
            # accept.
            return ScanVerdict(clean=False, code=REJECT_UNAVAILABLE)
        return self._interpret(raw)

    def _instream(self, data: bytes) -> bytes:
        sock = self._connect()
        try:
            sock.sendall(b"zINSTREAM\0")
            for start in range(0, len(data), _INSTREAM_CHUNK):
                chunk = data[start : start + _INSTREAM_CHUNK]
                sock.sendall(len(chunk).to_bytes(4, "big") + chunk)
            sock.sendall(b"\x00\x00\x00\x00")
            buffer = bytearray()
            while len(buffer) < _RESPONSE_LIMIT:
                part = sock.recv(_RESPONSE_LIMIT)
                if not part:
                    break
                buffer.extend(part)
                if buffer.endswith(b"\0"):
                    break
            return bytes(buffer)
        finally:
            try:
                sock.close()
            except OSError:
                pass

    @staticmethod
    def _interpret(raw: bytes) -> ScanVerdict:
        text = raw.decode("utf-8", errors="replace").strip().strip("\x00")
        if not text:
            # A silent daemon is an unavailable daemon.
            return ScanVerdict(clean=False, code=REJECT_UNAVAILABLE)
        if text.endswith("OK") and "FOUND" not in text:
            return ScanVerdict.ok()
        if text.endswith("FOUND"):
            # "stream: Eicar-Test-Signature FOUND" -> signature in the
            # middle. Kept for the audit row only.
            signature = text.split(":", 1)[-1].strip()
            signature = signature[: -len("FOUND")].strip() or None
            return ScanVerdict(
                clean=False,
                code=REJECT_INFECTED,
                signature=signature,
            )
        # "ERROR", "INSTREAM size limit exceeded", or anything this
        # adapter does not understand.
        return ScanVerdict(clean=False, code=REJECT_UNAVAILABLE)


def build_media_scanner(settings) -> MediaScanner:
    """Select the adapter from ``Settings``.

    Unknown values resolve to :class:`DisabledScanner` rather than
    raising: a typo in the operator's environment must not become a
    boot-time crash of the whole backend (the AI-tutor guard's cost, ADR
    0142 / R23 runbook §7.2), and it must not become an accept either.
    """
    selected = (getattr(settings, "media_scanner", "") or "").strip().lower()
    if selected == "clamd":
        return ClamdScanner(
            host=settings.media_scanner_host,
            port=settings.media_scanner_port,
            socket_path=settings.media_scanner_socket,
            timeout_seconds=settings.media_scanner_timeout_seconds,
        )
    return DisabledScanner()


__all__ = [
    "REJECT_INFECTED",
    "REJECT_NOT_CONFIGURED",
    "REJECT_UNAVAILABLE",
    "ClamdScanner",
    "DisabledScanner",
    "MediaScanner",
    "ScanVerdict",
    "build_media_scanner",
]
