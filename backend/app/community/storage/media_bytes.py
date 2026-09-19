"""Server-side byte inspection + metadata scrubbing for community media
(WP-H5).

This module is the load-bearing security layer of the
``POST /community/media`` endpoint: it is the ONLY place where the
uploaded bytes are looked at, and every decision it makes is derived
from the bytes themselves — never from a client-supplied header, a
filename, or a file extension.

Three jobs, in order:

1. :func:`sniff_content_type` — content-type detection by **magic
   bytes**. A caller that renames ``evil.png`` to ``take.jpg`` and
   sends ``Content-Type: audio/mpeg`` gets the sniffed type
   (``image/png``), and the router rejects it because it does not
   match the declared one. ``None`` means "no recognized signature"
   → reject.

2. :func:`sanitize_media_bytes` — metadata scrubbing. The scrubbed
   body is what is persisted; the original bytes are dropped on the
   floor. Images lose EXIF/XMP/ICC/text chunks (GPS coordinates,
   camera serial numbers, editing history); MP3 loses its ID3v2
   header and ID3v1 trailer (artist/comment/geotag frames and
   embedded artwork); WAV loses every chunk that is not ``fmt ``
   or ``data`` (``LIST``/``INFO``/``id3 `` carry authoring metadata).

3. :func:`probe_duration_ms` — server-side duration measurement for
   the audio types, so the duration cap is enforced against the real
   file rather than a client-declared number.

**Why the accepted set is narrower than the pipeline allowlist.**
``services.media_upload_service.MEDIA_CONTENT_TYPE_ALLOWLIST``
(E09-R18) also names ``audio/mp4``, ``audio/ogg``, ``video/mp4`` and
``video/quicktime``. This module deliberately does NOT accept those:

* ``audio/mp4`` / ``video/mp4`` / ``video/quicktime`` — ISO-BMFF
  metadata lives in nested ``moov/udta/meta/ilst`` atoms; scrubbing
  it means rewriting the atom tree, and video additionally needs a
  transcode/AV-scan step this deployment does not have.
* ``audio/ogg`` — Vorbis comments live inside the codec packet
  stream; removing them means re-packetizing and re-computing page
  CRCs.

Accepting a type we cannot scrub would mean shipping a silent
metadata-egress path, so those types are refused at the router
boundary until a round lands a real scrubber for them
(``docs/security/community-threat-model.md`` → T-MEDIA-04).

Everything here is stdlib-only and byte-level — no Pillow, no
ffmpeg, no mutagen. The JPEG EXIF strip delegates to the existing
:func:`tasks.media_processing.strip_exif_from_jpeg` walker
(E09-R19) and then removes the remaining ``APPn``/``COM``
segments it leaves behind.
"""

from __future__ import annotations

import struct
from typing import Final

from ..tasks.media_processing import strip_exif_from_jpeg

# ---------------------------------------------------------------------------
# The router-level accepted set.
# ---------------------------------------------------------------------------

#: Content types the server accepts on ``POST /community/media``.
#: A strict SUBSET of ``MEDIA_CONTENT_TYPE_ALLOWLIST`` — see the
#: module docstring for why the four missing types are refused.
SNIFFABLE_CONTENT_TYPES: Final[frozenset[str]] = frozenset(
    {
        "image/jpeg",
        "image/png",
        "image/webp",
        "audio/mpeg",
        "audio/x-wav",
    }
)

#: Content types whose duration this module can measure from the
#: bytes. Images have no duration; the router skips the cap for them.
DURATION_BEARING_CONTENT_TYPES: Final[frozenset[str]] = frozenset(
    {"audio/mpeg", "audio/x-wav"}
)


class MediaBytesError(Exception):
    """Base class for byte-level rejections."""


class MediaBytesUnrecognized(MediaBytesError):
    """No known magic-byte signature matched the payload."""


class MediaBytesMalformed(MediaBytesError):
    """The signature matched but the container is structurally broken.

    A truncated / self-contradicting container is rejected rather than
    stored: a body we cannot fully walk is also a body we cannot prove
    we scrubbed.
    """


# ---------------------------------------------------------------------------
# 1) Magic-byte sniffing.
# ---------------------------------------------------------------------------

_PNG_SIGNATURE: Final[bytes] = b"\x89PNG\r\n\x1a\n"


def sniff_content_type(body: bytes) -> str | None:
    """Return the content type implied by ``body``'s magic bytes.

    Returns ``None`` when nothing matches. The function NEVER looks at
    a filename, an extension, or a client-sent header — that is the
    whole point of it (threat T-MEDIA-01: content-type confusion).
    """
    if len(body) < 12:
        return None
    # JPEG — SOI (FFD8) followed by any marker prefix (FF).
    if body[0:3] == b"\xff\xd8\xff":
        return "image/jpeg"
    # PNG — the 8-byte signature.
    if body[0:8] == _PNG_SIGNATURE:
        return "image/png"
    # RIFF containers — WebP and WAV share the outer form.
    if body[0:4] == b"RIFF":
        if body[8:12] == b"WEBP":
            return "image/webp"
        if body[8:12] == b"WAVE":
            return "audio/x-wav"
        return None
    # MP3 — either an ID3v2 tag or a raw MPEG frame sync.
    if body[0:3] == b"ID3":
        return "audio/mpeg"
    if body[0] == 0xFF and (body[1] & 0xE0) == 0xE0 and _mpeg_frame_length(body, 0):
        return "audio/mpeg"
    return None


# ---------------------------------------------------------------------------
# 2) Metadata scrubbing.
# ---------------------------------------------------------------------------


def sanitize_media_bytes(body: bytes, *, content_type: str) -> bytes:
    """Return ``body`` with every metadata carrier we know about removed.

    ``content_type`` MUST be the sniffed type, not the declared one —
    the router enforces that ordering. An unknown type raises rather
    than passing the bytes through unscrubbed (fail-closed: a type we
    have no scrubber for must never reach storage).
    """
    if content_type == "image/jpeg":
        return _sanitize_jpeg(body)
    if content_type == "image/png":
        return _sanitize_png(body)
    if content_type == "image/webp":
        return _sanitize_webp(body)
    if content_type == "audio/mpeg":
        return _sanitize_mp3(body)
    if content_type == "audio/x-wav":
        return _sanitize_wav(body)
    raise MediaBytesUnrecognized(content_type)


# --- JPEG -------------------------------------------------------------

_JPEG_COM: Final[int] = 0xFE
_JPEG_SOS: Final[int] = 0xDA
_JPEG_EOI_LOW: Final[int] = 0xD9


def _sanitize_jpeg(body: bytes) -> bytes:
    """Drop every ``APPn`` (0xE0–0xEF) and ``COM`` (0xFE) segment.

    The EXIF (``APP1``) segment is removed first by the existing
    E09-R19 walker so the two implementations agree on that marker;
    this pass then removes the metadata carriers that walker leaves
    behind — ``APP0`` (JFIF), ``APP2`` (ICC, which can embed a GPS
    block), ``APP13`` (Photoshop/IPTC, which carries XMP + location)
    and free-form ``COM`` comments.
    """
    stripped = strip_exif_from_jpeg(body)
    if len(stripped) < 4 or stripped[0:2] != b"\xff\xd8":
        raise MediaBytesMalformed("jpeg: missing SOI")
    out = bytearray(b"\xff\xd8")
    index = 2
    length = len(stripped)
    saw_sos = False
    while index < length:
        if stripped[index] != 0xFF:
            raise MediaBytesMalformed("jpeg: expected marker prefix")
        while index < length and stripped[index] == 0xFF:
            index += 1
        if index >= length:
            raise MediaBytesMalformed("jpeg: truncated marker")
        marker = stripped[index]
        index += 1
        if marker == _JPEG_EOI_LOW:
            out += b"\xff\xd9"
            break
        if 0xD0 <= marker <= 0xD7 or marker == 0x01:
            out += bytes((0xFF, marker))
            continue
        if index + 2 > length:
            raise MediaBytesMalformed("jpeg: truncated segment length")
        seg_length = struct.unpack(">H", stripped[index : index + 2])[0]
        if seg_length < 2:
            raise MediaBytesMalformed("jpeg: bogus segment length")
        seg_end = index + seg_length
        if seg_end > length:
            raise MediaBytesMalformed("jpeg: segment overruns body")
        drop = (0xE0 <= marker <= 0xEF) or marker == _JPEG_COM
        if not drop:
            out += bytes((0xFF, marker))
            out += stripped[index:seg_end]
        index = seg_end
        if marker == _JPEG_SOS:
            # Entropy-coded data follows SOS with no length field —
            # copy the remainder verbatim (metadata cannot live there).
            saw_sos = True
            out += stripped[index:]
            break
    if not saw_sos:
        raise MediaBytesMalformed("jpeg: no scan data")
    return bytes(out)


# --- PNG --------------------------------------------------------------

#: The only PNG chunks that survive. Everything else — ``eXIf``,
#: ``tEXt``/``zTXt``/``iTXt`` (which is where XMP and GPS live),
#: ``tIME``, ``iCCP``, private chunks — is dropped. The kept set is
#: exactly what a decoder needs to render the image.
_PNG_KEEP_CHUNKS: Final[frozenset[bytes]] = frozenset(
    {b"IHDR", b"PLTE", b"IDAT", b"IEND", b"tRNS", b"acTL", b"fcTL", b"fdAT"}
)


def _sanitize_png(body: bytes) -> bytes:
    if body[0:8] != _PNG_SIGNATURE:
        raise MediaBytesMalformed("png: bad signature")
    out = bytearray(_PNG_SIGNATURE)
    index = 8
    length = len(body)
    saw_iend = False
    while index + 8 <= length:
        (chunk_length,) = struct.unpack(">I", body[index : index + 4])
        chunk_type = body[index + 4 : index + 8]
        chunk_end = index + 8 + chunk_length + 4  # +4 CRC
        if chunk_end > length:
            raise MediaBytesMalformed("png: chunk overruns body")
        if chunk_type in _PNG_KEEP_CHUNKS:
            out += body[index:chunk_end]
        index = chunk_end
        if chunk_type == b"IEND":
            saw_iend = True
            break
    if not saw_iend:
        raise MediaBytesMalformed("png: missing IEND")
    return bytes(out)


# --- WebP -------------------------------------------------------------

#: WebP chunks carrying metadata. ``VP8X`` flag bits 3 (EXIF) and 4
#: (XMP) and 5 (ICC) are cleared when the matching chunk is removed,
#: so the rewritten file stays self-consistent.
_WEBP_DROP_CHUNKS: Final[frozenset[bytes]] = frozenset({b"EXIF", b"XMP ", b"ICCP"})
_WEBP_VP8X_ICC_BIT: Final[int] = 0b0010_0000
_WEBP_VP8X_EXIF_BIT: Final[int] = 0b0000_1000
_WEBP_VP8X_XMP_BIT: Final[int] = 0b0000_0100


def _sanitize_webp(body: bytes) -> bytes:
    if body[0:4] != b"RIFF" or body[8:12] != b"WEBP":
        raise MediaBytesMalformed("webp: bad RIFF/WEBP header")
    (declared,) = struct.unpack("<I", body[4:8])
    if declared + 8 > len(body):
        raise MediaBytesMalformed("webp: RIFF size overruns body")
    payload = bytearray()
    index = 12
    limit = min(len(body), declared + 8)
    while index + 8 <= limit:
        chunk_type = body[index : index + 4]
        (chunk_length,) = struct.unpack("<I", body[index + 4 : index + 8])
        padded = chunk_length + (chunk_length & 1)
        chunk_end = index + 8 + padded
        if chunk_end > limit:
            raise MediaBytesMalformed("webp: chunk overruns body")
        if chunk_type in _WEBP_DROP_CHUNKS:
            index = chunk_end
            continue
        if chunk_type == b"VP8X" and chunk_length >= 1:
            flags = body[index + 8]
            flags &= ~(_WEBP_VP8X_ICC_BIT | _WEBP_VP8X_EXIF_BIT | _WEBP_VP8X_XMP_BIT)
            payload += body[index : index + 8]
            payload += bytes((flags & 0xFF,))
            payload += body[index + 9 : chunk_end]
        else:
            payload += body[index:chunk_end]
        index = chunk_end
    if not payload:
        raise MediaBytesMalformed("webp: no image chunks")
    return b"RIFF" + struct.pack("<I", len(payload) + 4) + b"WEBP" + bytes(payload)


# --- MP3 --------------------------------------------------------------


def _sanitize_mp3(body: bytes) -> bytes:
    """Drop the ID3v2 header and the ID3v1 trailer.

    ID3v2 frames carry free-form comments, embedded artwork and — via
    ``GEOB``/``TXXX`` — arbitrary payloads including geotags. The
    audio itself starts at the first MPEG frame sync; everything
    before it and the 128-byte ``TAG`` trailer after it is metadata.
    """
    start = _id3v2_payload_offset(body)
    end = len(body)
    if end - start >= 128 and body[end - 128 : end - 125] == b"TAG":
        end -= 128
    audio = body[start:end]
    if not audio or not _mpeg_frame_length(audio, 0):
        raise MediaBytesMalformed("mp3: no MPEG frame after tag strip")
    return audio


def _id3v2_payload_offset(body: bytes) -> int:
    """Byte offset of the first non-ID3v2 byte."""
    if len(body) < 10 or body[0:3] != b"ID3":
        return 0
    flags = body[5]
    size = 0
    for byte in body[6:10]:
        # Syncsafe integer — 7 bits per byte.
        size = (size << 7) | (byte & 0x7F)
    offset = 10 + size
    if flags & 0x10:  # footer present
        offset += 10
    return min(offset, len(body))


# --- WAV --------------------------------------------------------------

#: RIFF/WAVE chunks that survive. ``LIST``/``INFO``, ``id3 ``,
#: ``bext`` (broadcast metadata, carries an originator + a date) and
#: ``iXML`` are all dropped.
_WAV_KEEP_CHUNKS: Final[frozenset[bytes]] = frozenset({b"fmt ", b"data", b"fact"})


def _sanitize_wav(body: bytes) -> bytes:
    payload, _fmt, _data_size = _walk_wav(body)
    return b"RIFF" + struct.pack("<I", len(payload) + 4) + b"WAVE" + payload


def _walk_wav(body: bytes) -> tuple[bytes, bytes | None, int]:
    """Return ``(kept_payload, fmt_chunk_body, data_chunk_size)``."""
    if body[0:4] != b"RIFF" or body[8:12] != b"WAVE":
        raise MediaBytesMalformed("wav: bad RIFF/WAVE header")
    (declared,) = struct.unpack("<I", body[4:8])
    limit = min(len(body), declared + 8)
    payload = bytearray()
    fmt_body: bytes | None = None
    data_size = 0
    index = 12
    while index + 8 <= limit:
        chunk_type = body[index : index + 4]
        (chunk_length,) = struct.unpack("<I", body[index + 4 : index + 8])
        padded = chunk_length + (chunk_length & 1)
        chunk_end = index + 8 + padded
        if chunk_end > limit:
            raise MediaBytesMalformed("wav: chunk overruns body")
        if chunk_type in _WAV_KEEP_CHUNKS:
            payload += body[index:chunk_end]
            if chunk_type == b"fmt ":
                fmt_body = body[index + 8 : index + 8 + chunk_length]
            elif chunk_type == b"data":
                data_size = chunk_length
        index = chunk_end
    if fmt_body is None or data_size == 0:
        raise MediaBytesMalformed("wav: missing fmt/data chunk")
    return bytes(payload), fmt_body, data_size


# ---------------------------------------------------------------------------
# 3) Duration probing.
# ---------------------------------------------------------------------------

#: Hard ceiling on the number of MPEG frames the duration walker
#: visits. A 5-minute 320 kbps MP3 is ~11 500 frames; the cap keeps a
#: hostile "millions of 32-byte frames" body from turning the probe
#: into a CPU sink (threat T-MEDIA-05).
_MP3_MAX_FRAMES: Final[int] = 200_000

_MPEG_BITRATES_V1_L3: Final[tuple[int, ...]] = (
    0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0,
)
_MPEG_BITRATES_V2_L3: Final[tuple[int, ...]] = (
    0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0,
)
_MPEG_SAMPLE_RATES: Final[dict[int, tuple[int, int, int]]] = {
    # version bits -> (rate for index 0, 1, 2)
    3: (44100, 48000, 32000),  # MPEG 1
    2: (22050, 24000, 16000),  # MPEG 2
    0: (11025, 12000, 8000),  # MPEG 2.5
}


def probe_duration_ms(body: bytes, *, content_type: str) -> int | None:
    """Measure the duration from the bytes, or ``None`` when the type
    carries no duration (images).

    Raises :class:`MediaBytesMalformed` when the container claims a
    duration-bearing type but cannot be walked.
    """
    if content_type == "audio/x-wav":
        return _wav_duration_ms(body)
    if content_type == "audio/mpeg":
        return _mp3_duration_ms(body)
    return None


def _wav_duration_ms(body: bytes) -> int:
    _payload, fmt_body, data_size = _walk_wav(body)
    if fmt_body is None or len(fmt_body) < 16:
        raise MediaBytesMalformed("wav: short fmt chunk")
    (_fmt_tag, channels, sample_rate, byte_rate, _align, bits) = struct.unpack(
        "<HHIIHH", fmt_body[:16]
    )
    if byte_rate <= 0:
        if sample_rate <= 0 or channels <= 0 or bits <= 0:
            raise MediaBytesMalformed("wav: unusable fmt chunk")
        byte_rate = sample_rate * channels * (bits // 8)
    if byte_rate <= 0:
        raise MediaBytesMalformed("wav: zero byte rate")
    return int(data_size * 1000 / byte_rate)


def _mp3_duration_ms(body: bytes) -> int:
    audio = body[_id3v2_payload_offset(body) :]
    total_ms = 0.0
    index = 0
    frames = 0
    length = len(audio)
    while index + 4 <= length and frames < _MP3_MAX_FRAMES:
        frame = _mpeg_frame_length(audio, index)
        if frame is None:
            # Resync: scan forward for the next sync word.
            next_sync = audio.find(b"\xff", index + 1)
            if next_sync < 0:
                break
            index = next_sync
            continue
        frame_length, samples, sample_rate = frame
        total_ms += samples * 1000.0 / sample_rate
        index += frame_length
        frames += 1
    if frames == 0:
        raise MediaBytesMalformed("mp3: no decodable frames")
    return int(total_ms)


def _mpeg_frame_length(body: bytes, offset: int) -> tuple[int, int, int] | None:
    """Return ``(frame_bytes, samples_per_frame, sample_rate)`` for the
    MPEG audio frame at ``offset``, or ``None`` when the header is not
    a valid Layer III frame.

    Only Layer III is recognized — that is what ``audio/mpeg`` means in
    practice, and a narrow parser is a small parser.
    """
    if offset + 4 > len(body):
        return None
    b0, b1, b2, b3 = body[offset : offset + 4]
    if b0 != 0xFF or (b1 & 0xE0) != 0xE0:
        return None
    version_bits = (b1 >> 3) & 0b11
    layer_bits = (b1 >> 1) & 0b11
    if version_bits == 1 or layer_bits != 0b01:  # reserved version / not Layer III
        return None
    bitrate_index = (b2 >> 4) & 0x0F
    sample_rate_index = (b2 >> 2) & 0b11
    if bitrate_index in (0, 15) or sample_rate_index == 3:
        return None
    rates = _MPEG_SAMPLE_RATES.get(version_bits)
    if rates is None:
        return None
    sample_rate = rates[sample_rate_index]
    if version_bits == 3:
        bitrate = _MPEG_BITRATES_V1_L3[bitrate_index] * 1000
        samples = 1152
    else:
        bitrate = _MPEG_BITRATES_V2_L3[bitrate_index] * 1000
        samples = 576
    if bitrate <= 0:
        return None
    padding = (b2 >> 1) & 1
    frame_length = int(samples // 8 * bitrate / sample_rate) + padding
    if frame_length <= 4:
        return None
    return frame_length, samples, sample_rate


__all__ = [
    "DURATION_BEARING_CONTENT_TYPES",
    "MediaBytesError",
    "MediaBytesMalformed",
    "MediaBytesUnrecognized",
    "SNIFFABLE_CONTENT_TYPES",
    "probe_duration_ms",
    "sanitize_media_bytes",
    "sniff_content_type",
]
