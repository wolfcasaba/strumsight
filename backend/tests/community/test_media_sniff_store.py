"""Javító sáv R27 — magic-byte sniffing and the content-addressed store.

The two lowest layers of the Community media pipeline, measured on their
own so a failure here names the layer instead of the whole upload.

Acceptance map (brief §"Backend", threat model A6.2.1):

* **A1 — the decision is the BYTES.** A ``.jpg`` filename, an
  ``image/jpeg`` multipart header and a client-declared kind are all
  attacker-controlled, so none of them reaches :func:`sniff_media` at
  all: the function's signature takes ``bytes`` and nothing else. The
  renamed-payload cells below prove the consequence — an SVG called
  ``holiday.jpg`` is rejected, and a real JPEG called ``notes.txt`` is
  accepted, because the name was never read.
* **A2 — allowlist, not blocklist.** Every family the table names is
  accepted; everything else is rejected by ABSENCE. The cells walk PDF,
  ZIP, ELF, GIF, a bare shell script and a ``RIFF``/``AVI`` container —
  none of which needed a rule of its own to be refused.
* **A3 — the two scriptable families are named.** SVG and HTML get
  their own rejection code so the operator log distinguishes "someone
  uploaded markup" from "unknown format", including through leading
  whitespace and a UTF-8 BOM.
* **A4 — polyglots do not survive the sniff's ORDER.** A JPEG with a ZIP
  appended still sniffs as a JPEG (the re-encode is what drops the tail —
  that cell lives in ``test_media_pipeline.py``); a file that is a ZIP
  first is a ZIP, not an image.
* **A5 — empty is its own code.** A zero-byte part is a distinct,
  nameable rejection, not "unsupported".
* **A6 — the store has no path input.** Every path segment is derived
  from a digest the store computed itself; a corrupted digest raises
  rather than escaping the root. The traversal cells feed the store the
  strings an attacker would have to get into the row to escape.
* **A7 — deletion is refcounted.** Two rows converging on one file (the
  dedup that content addressing gives away for free) must not let one
  owner's delete blank the other's post.
"""

from __future__ import annotations

import io

import pytest
from PIL import Image

from app.community.media.sniff import (
    KIND_AUDIO,
    KIND_IMAGE,
    MEDIA_TYPE_JPEG,
    MEDIA_TYPE_MP3,
    MEDIA_TYPE_OGG,
    MEDIA_TYPE_PNG,
    MEDIA_TYPE_WAV,
    MEDIA_TYPE_WEBP,
    REJECT_EMPTY,
    REJECT_SCRIPTABLE,
    REJECT_UNSUPPORTED,
    MediaSniffError,
    sniff_media,
)
from app.community.media.store import FileMediaStore, MediaStoreError, sha256_hex

# ---------------------------------------------------------------------------
# Fixture bytes. The image families are produced by Pillow (a real encoder,
# not a hand-written header), so a cell that passes proves the byte string a
# real device would actually send is accepted.
# ---------------------------------------------------------------------------


def _encoded(fmt: str, mode: str = "RGB", size: tuple[int, int] = (8, 6)) -> bytes:
    buffer = io.BytesIO()
    Image.new(mode, size, color=(120, 40, 200) if mode == "RGB" else None).save(
        buffer, format=fmt
    )
    return buffer.getvalue()


def _jpeg() -> bytes:
    return _encoded("JPEG")


def _png() -> bytes:
    return _encoded("PNG")


def _webp() -> bytes:
    return _encoded("WEBP")


def _wav() -> bytes:
    """A minimal but structurally real RIFF/WAVE container."""
    pcm = b"\x00\x00" * 16
    fmt_chunk = (
        b"fmt "
        + (16).to_bytes(4, "little")
        + (1).to_bytes(2, "little")
        + (1).to_bytes(2, "little")
        + (8000).to_bytes(4, "little")
        + (16000).to_bytes(4, "little")
        + (2).to_bytes(2, "little")
        + (16).to_bytes(2, "little")
    )
    data_chunk = b"data" + len(pcm).to_bytes(4, "little") + pcm
    body = b"WAVE" + fmt_chunk + data_chunk
    return b"RIFF" + len(body).to_bytes(4, "little") + body


_SVG = b'<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>'
_HTML = b"<!DOCTYPE html><html><body><script>alert(1)</script></body></html>"
_ZIP = b"PK\x03\x04" + b"\x00" * 60
_PDF = b"%PDF-1.7\n%\xe2\xe3\xcf\xd3\n1 0 obj\n"
_ELF = b"\x7fELF\x02\x01\x01\x00" + b"\x00" * 56
_GIF = b"GIF89a" + b"\x00" * 32
_SHELL = b"#!/bin/sh\nrm -rf /\n"
_AVI = b"RIFF" + (64).to_bytes(4, "little") + b"AVI LIST" + b"\x00" * 48
_ID3_MP3 = b"ID3\x04\x00\x00\x00\x00\x00\x00" + b"\xff\xfb\x90\x64" + b"\x00" * 32
_BARE_MP3 = b"\xff\xfb\x90\x64" + b"\x00" * 64
_OGG_OPUS = b"OggS\x00\x02" + b"\x00" * 20 + b"OpusHead\x01\x02" + b"\x00" * 32
_OGG_THEORA = b"OggS\x00\x02" + b"\x00" * 20 + b"\x80theora" + b"\x00" * 32


class TestSniffAcceptsTheEightFamilies:
    """A2 — every allowlisted family, by the bytes a real encoder emits."""

    def test_jpeg(self):
        sniffed = sniff_media(_jpeg())
        assert (sniffed.kind, sniffed.media_type) == (KIND_IMAGE, MEDIA_TYPE_JPEG)

    def test_png(self):
        sniffed = sniff_media(_png())
        assert (sniffed.kind, sniffed.media_type) == (KIND_IMAGE, MEDIA_TYPE_PNG)

    def test_webp(self):
        sniffed = sniff_media(_webp())
        assert (sniffed.kind, sniffed.media_type) == (KIND_IMAGE, MEDIA_TYPE_WEBP)

    def test_wav(self):
        sniffed = sniff_media(_wav())
        assert (sniffed.kind, sniffed.media_type) == (KIND_AUDIO, MEDIA_TYPE_WAV)

    def test_mp3_with_an_id3_header(self):
        sniffed = sniff_media(_ID3_MP3)
        assert (sniffed.kind, sniffed.media_type) == (KIND_AUDIO, MEDIA_TYPE_MP3)

    def test_mp3_by_bare_frame_sync(self):
        sniffed = sniff_media(_BARE_MP3)
        assert (sniffed.kind, sniffed.media_type) == (KIND_AUDIO, MEDIA_TYPE_MP3)

    def test_ogg_opus(self):
        sniffed = sniff_media(_OGG_OPUS)
        assert (sniffed.kind, sniffed.media_type) == (KIND_AUDIO, MEDIA_TYPE_OGG)

    def test_adts_aac_is_not_mistaken_for_an_mp3_frame_sync(self):
        """The ``FF F1`` ADTS header is a strict prefix of the 11-bit MPEG
        sync pattern; testing the weaker signature first would label an
        AAC file ``audio/mpeg``. The ORDER inside ``sniff_media`` is what
        this cell pins."""
        sniffed = sniff_media(b"\xff\xf1" + b"\x00" * 64)
        assert sniffed.media_type == "audio/aac"


class TestSniffRejectsEverythingElse:
    """A2/A3/A5 — rejection by absence, with the two named exceptions."""

    @pytest.mark.parametrize(
        "payload",
        [
            pytest.param(_ZIP, id="zip"),
            pytest.param(_PDF, id="pdf"),
            pytest.param(_ELF, id="elf"),
            pytest.param(_GIF, id="gif"),
            pytest.param(_AVI, id="riff-avi"),
            pytest.param(_OGG_THEORA, id="ogg-video"),
            pytest.param(b"\x00" * 128, id="zero-filled"),
            pytest.param(b"not media at all, just prose", id="plain-text"),
        ],
    )
    def test_unknown_families_are_unsupported(self, payload):
        with pytest.raises(MediaSniffError) as raised:
            sniff_media(payload)
        assert raised.value.code == REJECT_UNSUPPORTED

    @pytest.mark.parametrize(
        "payload",
        [
            pytest.param(_SVG, id="svg"),
            pytest.param(_HTML, id="html"),
            pytest.param(b"   \n\t" + _SVG, id="svg-behind-whitespace"),
            pytest.param(b"\xef\xbb\xbf" + _SVG, id="svg-behind-utf8-bom"),
            pytest.param(b"<?xml version='1.0'?>" + _SVG, id="svg-behind-xml-decl"),
            pytest.param(_SHELL, id="shell-script"),
        ],
    )
    def test_scriptable_documents_get_their_own_code(self, payload):
        with pytest.raises(MediaSniffError) as raised:
            sniff_media(payload)
        assert raised.value.code == REJECT_SCRIPTABLE

    def test_empty_upload_is_its_own_code(self):
        with pytest.raises(MediaSniffError) as raised:
            sniff_media(b"")
        assert raised.value.code == REJECT_EMPTY


class TestTheFilenameNeverParticipates:
    """A1 — the renamed-payload matrix.

    ``sniff_media`` takes bytes and nothing else, so these cells are
    really about the CALLER contract: there is no parameter through which
    a name or a declared content-type could influence the verdict. The
    two directions are both load-bearing.
    """

    def test_svg_renamed_to_jpg_is_still_rejected(self):
        # The attacker's move: `payload.svg` -> `holiday.jpg`, with an
        # `image/jpeg` multipart Content-Type to match.
        with pytest.raises(MediaSniffError) as raised:
            sniff_media(_SVG)
        assert raised.value.code == REJECT_SCRIPTABLE

    def test_a_real_jpeg_under_a_txt_name_is_still_accepted(self):
        # The mirror image: an honest user whose file has a wrong or
        # missing extension is not punished for it.
        assert sniff_media(_jpeg()).media_type == MEDIA_TYPE_JPEG

    def test_a_png_body_behind_a_jpeg_extension_sniffs_as_png(self):
        """The stored + served content-type is the SERVER's verdict, so a
        mislabelled upload cannot make the download endpoint echo an
        attacker-chosen ``Content-Type`` at a browser."""
        assert sniff_media(_png()).media_type == MEDIA_TYPE_PNG


class TestPolyglots:
    """A4 — order matters, and the sniff is only the first half."""

    def test_jpeg_with_a_zip_tail_sniffs_as_jpeg(self):
        polyglot = _jpeg() + _ZIP
        assert sniff_media(polyglot).media_type == MEDIA_TYPE_JPEG

    def test_zip_with_a_jpeg_tail_is_rejected(self):
        polyglot = _ZIP + _jpeg()
        with pytest.raises(MediaSniffError) as raised:
            sniff_media(polyglot)
        assert raised.value.code == REJECT_UNSUPPORTED

    def test_html_with_a_png_tail_is_scriptable(self):
        with pytest.raises(MediaSniffError) as raised:
            sniff_media(_HTML + _png())
        assert raised.value.code == REJECT_SCRIPTABLE


class TestContentAddressedStore:
    """A6/A7 — no path input, and a refcounted unlink."""

    def test_the_path_is_derived_from_the_content_digest(self, tmp_path):
        store = FileMediaStore(tmp_path / "media")
        payload = _png()
        digest, path = store.put(payload)

        assert digest == sha256_hex(payload)
        assert path.read_bytes() == payload
        # `<root>/<aa>/<bb>/<digest>` — the two shard levels come from the
        # digest itself, so there is no segment a request could supply.
        assert path.name == digest
        assert path.parent.name == digest[2:4]
        assert path.parent.parent.name == digest[0:2]
        assert path.is_relative_to(store.root)

    def test_storing_identical_bytes_twice_is_a_no_op(self, tmp_path):
        store = FileMediaStore(tmp_path / "media")
        first_digest, first_path = store.put(_png())
        second_digest, second_path = store.put(_png())
        assert (first_digest, first_path) == (second_digest, second_path)

    @pytest.mark.parametrize(
        "candidate",
        [
            pytest.param("../../etc/passwd", id="dot-dot-slash"),
            pytest.param("..", id="dot-dot"),
            pytest.param("/etc/passwd", id="absolute"),
            pytest.param("a" * 63, id="too-short"),
            pytest.param("A" * 64, id="uppercase-hex"),
            pytest.param("g" * 64, id="non-hex"),
            pytest.param("", id="empty"),
            pytest.param("a" * 32 + "/" + "b" * 31, id="embedded-separator"),
        ],
    )
    def test_a_non_digest_never_becomes_a_path(self, tmp_path, candidate):
        """A6 — the containment assertion is belt-and-braces; the digest
        SHAPE check is the actual guard, and it refuses every string an
        attacker would need to get into the row to escape the root."""
        store = FileMediaStore(tmp_path / "media")
        with pytest.raises(MediaStoreError):
            store.resolve(candidate)
        assert store.exists(candidate) is False

    def test_reading_a_missing_file_raises_rather_than_returning_empty(self, tmp_path):
        store = FileMediaStore(tmp_path / "media")
        with pytest.raises(MediaStoreError):
            store.read(sha256_hex(b"never stored"))

    def test_delete_keeps_the_file_while_another_row_references_it(self, tmp_path):
        """A7 — dedup means two owners can share one file; the second
        owner's post must not go blank when the first one deletes."""
        store = FileMediaStore(tmp_path / "media")
        digest, path = store.put(_png())

        assert store.delete(digest, other_references=1) is False
        assert path.exists()

        assert store.delete(digest, other_references=0) is True
        assert not path.exists()

    def test_delete_prunes_the_now_empty_shard_directories(self, tmp_path):
        store = FileMediaStore(tmp_path / "media")
        digest, path = store.put(_png())
        shard = path.parent
        store.delete(digest, other_references=0)
        assert not shard.exists()
        assert store.root.exists()

    def test_delete_of_an_unknown_digest_is_a_no_op_not_a_raise(self, tmp_path):
        """The DELETE endpoint is idempotent; a row whose file is already
        gone must not turn a retried delete into a 500."""
        store = FileMediaStore(tmp_path / "media")
        assert store.delete(sha256_hex(b"absent"), other_references=0) is True
        assert store.delete("not-a-digest", other_references=0) is False
