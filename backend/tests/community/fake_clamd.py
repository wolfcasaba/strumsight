"""Javító sáv R27 — a throwaway clamd stand-in, shared by two suites.

Lives next to the tests rather than inside one of them because BOTH the
adapter suite (``test_media_scanner.py``) and the HTTP suite
(``test_media_router.py``) need a daemon that actually speaks the
``INSTREAM`` framing: the router's happy path runs through
``build_media_scanner`` and therefore through a real socket, which is the
only way the "the flag is on AND clamd is up" configuration gets
measured end to end.

The server is an ephemeral-port TCP listener that serves connections in a
loop until :meth:`FakeClamd.close`. Per connection it parses the command,
reassembles the chunked stream, optionally waits (the timeout cell), then
writes the answer the test asked for — or closes silently when the answer
is ``None`` (the "silent daemon" cell).

Serving MORE than one connection is load-bearing for the router suite: an
upload endpoint that is exercised twice in one test opens two clamd
sessions, and a single-shot stand-in would turn the second upload into a
``scanner_unavailable`` rejection that looks like a product bug.
"""

from __future__ import annotations

import socket
import threading


class FakeClamd:
    """A throwaway TCP server that speaks just enough ``INSTREAM``.

    ``answer`` is the raw byte string sent back after the terminator; a
    ``None`` answer closes the connection without writing anything, and
    ``hang_seconds`` delays the answer past the adapter's timeout.
    """

    def __init__(
        self,
        answer: bytes | None,
        *,
        hang_seconds: float = 0.0,
    ) -> None:
        self._answer = answer
        self._hang = hang_seconds
        self._closing = threading.Event()
        self._server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self._server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self._server.bind(("127.0.0.1", 0))
        self._server.listen(8)
        self._server.settimeout(0.5)
        #: Everything the client streamed on the LAST connection, with the
        #: framing stripped — the payload-fidelity assertion reads this.
        self.received = bytearray()
        self.command = b""
        #: How many sessions the daemon has served, so a suite can assert
        #: that the scan really ran once per upload.
        self.sessions = 0
        self._thread = threading.Thread(target=self._serve_forever, daemon=True)
        self._thread.start()

    @property
    def port(self) -> int:
        return int(self._server.getsockname()[1])

    def _serve_forever(self) -> None:
        while not self._closing.is_set():
            try:
                conn, _ = self._server.accept()
            except TimeoutError:
                continue
            except OSError:
                return
            try:
                self._serve_one(conn)
            finally:
                try:
                    conn.close()
                except OSError:
                    pass

    def _serve_one(self, conn: socket.socket) -> None:
        received = bytearray()
        try:
            conn.settimeout(5.0)
            buffer = bytearray()
            # The command is NUL-terminated (`zINSTREAM\0`).
            while b"\0" not in buffer:
                part = conn.recv(4096)
                if not part:
                    return
                buffer.extend(part)
            terminator = buffer.index(b"\0")
            command = bytes(buffer[:terminator])
            stream = bytearray(buffer[terminator + 1 :])
            while True:
                while len(stream) < 4:
                    part = conn.recv(65536)
                    if not part:
                        break
                    stream.extend(part)
                if len(stream) < 4:
                    break
                length = int.from_bytes(stream[:4], "big")
                if length == 0:
                    break
                del stream[:4]
                while len(stream) < length:
                    part = conn.recv(65536)
                    if not part:
                        break
                    stream.extend(part)
                received.extend(stream[:length])
                del stream[:length]
            self.command = command
            self.received = received
            self.sessions += 1
            if self._hang:
                self._closing.wait(self._hang)
            if self._answer is not None:
                conn.sendall(self._answer)
        except OSError:
            pass

    def close(self) -> None:
        self._closing.set()
        try:
            self._server.close()
        except OSError:
            pass
        self._thread.join(timeout=3.0)
