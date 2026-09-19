"""Magic-byte content sniffing for Community media (threat model A6.2.1).

The ONE place that answers "what are these bytes?". The answer is derived
exclusively from the byte string itself:

* the uploaded **filename** never participates — an attacker renames
  ``payload.svg`` to ``holiday.jpg`` for free;
* the multipart **Content-Type** never participates — it is a header the
  caller writes;
* the **declared kind** never participates — the client cannot tell the
  server that its HTML is an image.

Everything the sniffer does not positively recognise is rejected. That is
the load-bearing direction: an allowlist of eight signatures, not a
blocklist of dangerous ones. SVG, HTML, PDF, ZIP, ELF and shell scripts
are therefore all rejected by *absence*, and the two explicitly
script-shaped families (SVG / HTML) additionally get their own rejection
reason so the operator log says WHY.

Recognised families
-------------------

======  ============  ==============================================
kind    media type    signature (offset: bytes)
======  ============  ==============================================
image   image/jpeg    0: ``FF D8 FF``
image   image/png     0: ``89 50 4E 47 0D 0A 1A 0A``
image   image/webp    0: ``RIFF`` and 8: ``WEBP``
audio   audio/mpeg    0: ``ID3`` or an MPEG frame sync ``FF Ex/Fx``
audio   audio/wav     0: ``RIFF`` and 8: ``WAVE``
audio   audio/ogg     0: ``OggS`` (+ ``OpusHead``/``vorbis`` in page 1)
audio   audio/mp4     4: ``ftyp`` with an audio-capable brand
audio   audio/aac     0: ``FF F1`` / ``FF F9`` (ADTS)
======  ============  ==============================================

The MP3 frame-sync branch is deliberately the LAST test tried: eleven set
bits is a weak signature, and testing it first would let a ``FF F1`` ADTS
header (a strict prefix of the same pattern) be mislabelled. WebP and WAV
share the ``RIFF`` container, so both check the form-type at offset 8;
a ``RIFF`` file with any other form type is rejected rather than guessed.

The sniffer returns the SERVER's opinion of the media type. That opinion
is what the row stores and what the download endpoint later serves, so a
mislabelled upload cannot make the server echo an attacker-chosen
``Content-Type`` back to a browser.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Final

#: The two kinds the Community composer can attach.
KIND_IMAGE: Final[str] = "image"
KIND_AUDIO: Final[str] = "audio"

MEDIA_TYPE_JPEG: Final[str] = "image/jpeg"
MEDIA_TYPE_PNG: Final[str] = "image/png"
MEDIA_TYPE_WEBP: Final[str] = "image/webp"
MEDIA_TYPE_MP3: Final[str] = "audio/mpeg"
MEDIA_TYPE_WAV: Final[str] = "audio/wav"
MEDIA_TYPE_OGG: Final[str] = "audio/ogg"
MEDIA_TYPE_MP4: Final[str] = "audio/mp4"
MEDIA_TYPE_AAC: Final[str] = "audio/aac"

#: Rejection code for "the bytes are not one of the eight families".
REJECT_UNSUPPORTED: Final[str] = "unsupported_media_type"
#: Rejection code for the two scriptable families we name explicitly.
REJECT_SCRIPTABLE: Final[str] = "scriptable_media_rejected"
#: Rejection code for an empty upload.
REJECT_EMPTY: Final[str] = "empty_upload"

#: Longest signature window the sniffer inspects. 16 bytes covers the
#: ``RIFF....WEBP`` / ``....ftypM4A `` shapes; the OGG codec probe reads
#: further into the first page but only to CONFIRM an already-matched
#: ``OggS`` container.
_SNIFF_WINDOW: Final[int] = 16

#: ``ftyp`` major brands we accept as an audio-capable MP4. ``isom`` /
#: ``mp42`` are generic and can carry video too; the transcoder is the
#: layer that decides an audio-only output, so a video-capable container
#: is accepted here and normalised there (and rejected outright while the
#: audio transcoder is disabled, which is the default).
_MP4_AUDIO_BRANDS: Final[frozenset[bytes]] = frozenset(
    {
        b"M4A ",
        b"M4B ",
        b"mp41",
        b"mp42",
        b"isom",
        b"iso2",
        b"dash",
    }
)

#: Leading bytes that mark an XML / HTML document. Compared after
#: stripping leading ASCII whitespace and an optional UTF-8 BOM, because
#: ``  <svg`` and ``﻿<svg`` are the same attack.
_SCRIPTABLE_PREFIXES: Final[tuple[bytes, ...]] = (
    b"<?xml",
    b"<svg",
    b"<!doctype",
    b"<html",
    b"<!--",
    b"#!",
)


@dataclass(frozen=True)
class SniffedMedia:
    """What the byte string is, according to the server alone."""

    #: ``image`` or ``audio``.
    kind: str
    #: The IANA media type the server will store AND later serve.
    media_type: str


class MediaSniffError(Exception):
    """The bytes are not an accepted media family.

    ``code`` is the machine-readable rejection code the router echoes and
    the row persists — never a free-text message the client parses.
    """

    def __init__(self, code: str) -> None:
        super().__init__(code)
        self.code = code


def _looks_scriptable(data: bytes) -> bool:
    """True for XML/HTML/shebang documents (the SVG family included)."""
    head = data[:64]
    if head.startswith(b"\xef\xbb\xbf"):
        head = head[3:]
    head = head.lstrip(b" \t\r\n\f\v")
    lowered = head.lower()
    return any(lowered.startswith(prefix) for prefix in _SCRIPTABLE_PREFIXES)


def _is_mpeg_frame_sync(data: bytes) -> bool:
    """True for an MPEG-1/2 audio frame header (11 set sync bits).

    Rejects the two reserved encodings a real frame never carries — a
    reserved MPEG version (``00``) or a reserved layer (``00``) — so a
    random ``FF Ex`` pair inside an unrelated binary is less likely to be
    read as an MP3.
    """
    if len(data) < 2:
        return False
    if data[0] != 0xFF or (data[1] & 0xE0) != 0xE0:
        return False
    version = (data[1] >> 3) & 0x03
    layer = (data[1] >> 1) & 0x03
    return version != 0x01 and layer != 0x00


def _is_adts_aac(data: bytes) -> bool:
    """True for a raw ADTS AAC frame header (``FF F1`` / ``FF F9``)."""
    return len(data) >= 2 and data[0] == 0xFF and data[1] in (0xF1, 0xF9)


def _ogg_is_audio(data: bytes) -> bool:
    """Confirm an ``OggS`` container carries Opus or Vorbis.

    An Ogg stream can carry Theora video just as well; the codec name
    lives in the first page's identification packet, well inside the
    first 512 bytes for both codecs we accept.
    """
    window = data[:512]
    return b"OpusHead" in window or b"vorbis" in window


def sniff_media(data: bytes) -> SniffedMedia:
    """Return what ``data`` is, or raise :class:`MediaSniffError`.

    The function is total: every input either maps to one of the eight
    accepted families or raises. There is no "unknown, allow anyway"
    branch — that branch is the vulnerability this module exists to
    remove.
    """
    if not data:
        raise MediaSniffError(REJECT_EMPTY)
    if _looks_scriptable(data):
        # Named separately from the generic rejection so the log says
        # "someone tried to upload markup", which is the interesting
        # event, not "unknown format".
        raise MediaSniffError(REJECT_SCRIPTABLE)

    head = data[:_SNIFF_WINDOW]

    if head.startswith(b"\x89PNG\r\n\x1a\n"):
        return SniffedMedia(kind=KIND_IMAGE, media_type=MEDIA_TYPE_PNG)
    if head.startswith(b"\xff\xd8\xff"):
        return SniffedMedia(kind=KIND_IMAGE, media_type=MEDIA_TYPE_JPEG)
    if head.startswith(b"RIFF") and len(head) >= 12:
        form = head[8:12]
        if form == b"WEBP":
            return SniffedMedia(kind=KIND_IMAGE, media_type=MEDIA_TYPE_WEBP)
        if form == b"WAVE":
            return SniffedMedia(kind=KIND_AUDIO, media_type=MEDIA_TYPE_WAV)
        # A RIFF container of any other form type (AVI, ANI, …) is NOT
        # guessed at — the allowlist direction again.
        raise MediaSniffError(REJECT_UNSUPPORTED)
    if head.startswith(b"OggS"):
        if _ogg_is_audio(data):
            return SniffedMedia(kind=KIND_AUDIO, media_type=MEDIA_TYPE_OGG)
        raise MediaSniffError(REJECT_UNSUPPORTED)
    if len(head) >= 12 and head[4:8] == b"ftyp":
        if head[8:12] in _MP4_AUDIO_BRANDS:
            return SniffedMedia(kind=KIND_AUDIO, media_type=MEDIA_TYPE_MP4)
        raise MediaSniffError(REJECT_UNSUPPORTED)
    if head.startswith(b"ID3"):
        return SniffedMedia(kind=KIND_AUDIO, media_type=MEDIA_TYPE_MP3)
    if _is_adts_aac(head):
        return SniffedMedia(kind=KIND_AUDIO, media_type=MEDIA_TYPE_AAC)
    # LAST, deliberately: the weakest signature in the table.
    if _is_mpeg_frame_sync(head):
        return SniffedMedia(kind=KIND_AUDIO, media_type=MEDIA_TYPE_MP3)

    raise MediaSniffError(REJECT_UNSUPPORTED)


__all__ = [
    "KIND_AUDIO",
    "KIND_IMAGE",
    "MEDIA_TYPE_AAC",
    "MEDIA_TYPE_JPEG",
    "MEDIA_TYPE_MP3",
    "MEDIA_TYPE_MP4",
    "MEDIA_TYPE_OGG",
    "MEDIA_TYPE_PNG",
    "MEDIA_TYPE_WAV",
    "MEDIA_TYPE_WEBP",
    "REJECT_EMPTY",
    "REJECT_SCRIPTABLE",
    "REJECT_UNSUPPORTED",
    "MediaSniffError",
    "SniffedMedia",
    "sniff_media",
]
