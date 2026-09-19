"""Javító sáv R27 — the malware-scanner port and its two adapters.

Threat model **A6.2.5**. The measured claim of this module is a negative
one: there is no input, no configuration and no infrastructure failure
that makes an upload look *clean* without a scanner having actually said
so.

The clamd adapter is driven against a REAL socket — a throwaway TCP
server in a thread that speaks the ``INSTREAM`` framing — rather than a
monkeypatched method. A mock of ``_instream`` would only prove that the
interpreter maps strings to verdicts; the interesting failures (a refused
connect, a daemon that closes silently, a daemon that never answers) live
in the socket layer, and a fake at that seam is the only way to reach
them.

Acceptance map:

* **A1 — the disabled adapter REJECTS.** The fail-closed default is a
  refusal with a named code, never a pass-through. This cell is the one
  that would go green if someone "helpfully" added a ``NullScanner``.
* **A2 — a clean answer is the ONLY accept.** ``stream: OK`` passes;
  ``FOUND``, ``ERROR``, an unparseable answer and an empty answer are
  all rejects, each with the right code.
* **A3 — infrastructure failure is a reject.** Connection refused, a
  socket file that is not there, and a daemon that never answers within
  the timeout all map to ``scanner_unavailable``.
* **A4 — the signature is audit data.** The finding's name is parsed off
  the ``FOUND`` line and kept on the verdict, but it is attacker-
  influenced text: the router never echoes it (that half is asserted in
  ``test_media_router.py``).
* **A5 — selection fails closed.** ``build_media_scanner`` returns the
  disabled adapter for the default, for an unknown value and for a typo;
  only the exact string ``clamd`` selects the real one.
* **A6 — the payload actually reaches the daemon.** The bytes the
  adapter streams are byte-identical to the bytes handed in, chunk
  framing included — a scanner that is fed the wrong thing is a scanner
  that scanned nothing.
"""

from __future__ import annotations

import socket

import pytest
from fake_clamd import FakeClamd

from app.community.media.scanner import (
    REJECT_INFECTED,
    REJECT_NOT_CONFIGURED,
    REJECT_UNAVAILABLE,
    ClamdScanner,
    DisabledScanner,
    build_media_scanner,
)
from app.config import Settings


@pytest.fixture
def fake_clamd():
    servers: list[FakeClamd] = []

    def _factory(answer: bytes | None, *, hang_seconds: float = 0.0) -> FakeClamd:
        server = FakeClamd(answer, hang_seconds=hang_seconds)
        servers.append(server)
        return server

    try:
        yield _factory
    finally:
        for server in servers:
            server.close()


def _free_port() -> int:
    """A port nothing is listening on — the connection-refused cell."""
    probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    probe.bind(("127.0.0.1", 0))
    port = int(probe.getsockname()[1])
    probe.close()
    return port


class TestDisabledScannerRejects:
    """A1 — the fail-closed default is a refusal, not a pass-through."""

    def test_every_upload_is_rejected_with_a_named_code(self):
        verdict = DisabledScanner().scan(b"any bytes at all")
        assert verdict.clean is False
        assert verdict.code == REJECT_NOT_CONFIGURED

    def test_even_an_empty_payload_is_rejected(self):
        assert DisabledScanner().scan(b"").clean is False

    def test_the_adapter_names_itself_for_the_audit_row(self):
        assert DisabledScanner().name == "disabled"


class TestClamdVerdicts:
    """A2/A4 — only ``OK`` accepts; the finding's name is audit-only."""

    def test_ok_is_the_only_accept(self, fake_clamd):
        server = fake_clamd(b"stream: OK\0")
        scanner = ClamdScanner(port=server.port, timeout_seconds=5.0)
        verdict = scanner.scan(b"clean bytes")
        assert verdict.clean is True
        assert verdict.code is None

    def test_found_is_an_infection_with_the_signature_kept_for_audit(self, fake_clamd):
        server = fake_clamd(b"stream: Eicar-Test-Signature FOUND\0")
        scanner = ClamdScanner(port=server.port, timeout_seconds=5.0)
        verdict = scanner.scan(b"eicar-ish bytes")
        assert verdict.clean is False
        assert verdict.code == REJECT_INFECTED
        assert verdict.signature == "Eicar-Test-Signature"

    @pytest.mark.parametrize(
        "answer",
        [
            pytest.param(b"stream: ERROR\0", id="error"),
            pytest.param(b"INSTREAM size limit exceeded. ERROR\0", id="size-limit"),
            pytest.param(b"\xff\xfe not utf-8 at all\0", id="unparseable"),
            pytest.param(b"\0", id="empty-after-strip"),
            pytest.param(b"OK but with FOUND in it\0", id="ambiguous"),
        ],
    )
    def test_anything_that_is_not_a_clean_answer_rejects(self, fake_clamd, answer):
        server = fake_clamd(answer)
        scanner = ClamdScanner(port=server.port, timeout_seconds=5.0)
        verdict = scanner.scan(b"payload")
        assert verdict.clean is False, answer

    def test_a_silent_daemon_is_an_unavailable_daemon(self, fake_clamd):
        server = fake_clamd(None)
        scanner = ClamdScanner(port=server.port, timeout_seconds=5.0)
        verdict = scanner.scan(b"payload")
        assert verdict.clean is False
        assert verdict.code == REJECT_UNAVAILABLE

    def test_the_streamed_payload_reaches_the_daemon_byte_for_byte(self, fake_clamd):
        """A6 — the chunk framing must not corrupt or truncate the bytes;
        a scanner fed a prefix has not scanned the file."""
        server = fake_clamd(b"stream: OK\0")
        # Deliberately larger than the adapter's 64 KiB chunk so the
        # multi-chunk path is the one under measurement.
        payload = bytes(range(256)) * 700
        scanner = ClamdScanner(port=server.port, timeout_seconds=10.0)
        assert scanner.scan(payload).clean is True
        assert bytes(server.received) == payload
        assert server.command == b"zINSTREAM"


class TestClamdInfrastructureFailuresAreRejects:
    """A3 — we did not scan, so we do not accept."""

    def test_connection_refused_rejects(self):
        scanner = ClamdScanner(port=_free_port(), timeout_seconds=1.0)
        verdict = scanner.scan(b"payload")
        assert verdict.clean is False
        assert verdict.code == REJECT_UNAVAILABLE

    def test_a_missing_unix_socket_rejects(self, tmp_path):
        scanner = ClamdScanner(
            socket_path=str(tmp_path / "no-such.sock"),
            timeout_seconds=1.0,
        )
        verdict = scanner.scan(b"payload")
        assert verdict.clean is False
        assert verdict.code == REJECT_UNAVAILABLE

    def test_a_daemon_that_never_answers_rejects_on_timeout(self, fake_clamd):
        server = fake_clamd(b"stream: OK\0", hang_seconds=5.0)
        scanner = ClamdScanner(port=server.port, timeout_seconds=0.4)
        verdict = scanner.scan(b"payload")
        assert verdict.clean is False
        assert verdict.code == REJECT_UNAVAILABLE

    def test_scan_never_raises(self):
        """The port contract: the pipeline treats a raise as a crash, so
        an adapter that lets an OSError escape would turn a scanner
        outage into a 500 instead of a rejection."""
        scanner = ClamdScanner(host="", port=0, timeout_seconds=0.5)
        assert scanner.scan(b"payload").clean is False


class TestScannerSelectionFailsClosed:
    """A5 — only the exact string ``clamd`` buys a real scanner."""

    def test_the_default_settings_select_the_disabled_adapter(self):
        assert isinstance(build_media_scanner(Settings()), DisabledScanner)

    @pytest.mark.parametrize(
        "value",
        [
            pytest.param("", id="empty"),
            pytest.param("disabled", id="explicit-disabled"),
            pytest.param("clamdd", id="typo"),
            pytest.param("none", id="none"),
            pytest.param("off", id="off"),
            pytest.param("passthrough", id="wishful-passthrough"),
        ],
    )
    def test_anything_but_clamd_is_the_disabled_adapter(self, value):
        settings = Settings(media_scanner=value)
        assert isinstance(build_media_scanner(settings), DisabledScanner)

    @pytest.mark.parametrize("value", ["clamd", "CLAMD", "  Clamd  "])
    def test_clamd_is_selected_case_and_whitespace_insensitively(self, value):
        settings = Settings(media_scanner=value, media_scanner_port=3311)
        scanner = build_media_scanner(settings)
        assert isinstance(scanner, ClamdScanner)
        assert scanner.name == "clamd"

    def test_a_typo_does_not_crash_the_boot(self):
        """A typo in the operator's environment must not become a
        boot-time crash of the whole backend (the R23 runbook §7.2
        lesson) — and must not become an accept either."""
        scanner = build_media_scanner(Settings(media_scanner="clmad"))
        assert scanner.scan(b"payload").clean is False
