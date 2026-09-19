"""Re-encode / transcode adapters (threat model A6.2.4).

The rule this module enforces: **the bytes the server stores are the
bytes the server's own encoder produced.** Nothing an uploader wrote
survives to the download endpoint verbatim.

Images
------

:class:`PillowImageTranscoder` opens the upload with Pillow, verifies the
decode, downscales the longest edge to ``media_image_max_dimension`` when
needed, and re-encodes to JPEG (or WebP for images that carry alpha).
Three properties fall out of doing it this way rather than "validate and
copy":

* **EXIF / XMP / ICC are gone** — the new file is built from the decoded
  pixel buffer plus nothing. GPS coordinates in a practice photo are a
  privacy leak the data inventory would otherwise have to carry.
* **Polyglot tails are gone** — a JPEG with a ZIP or a PHP payload
  appended decodes to the same pixels, and the re-encode drops
  everything after the image data.
* **Decompression bombs are bounded** — ``Image.MAX_IMAGE_PIXELS``
  raises on absurd canvases before any allocation of that size.

Pillow is a hard dependency (``backend/requirements.txt``); an
ImportError here is a broken install, not a configuration state, so it
is not caught.

Audio
-----

Audio needs an out-of-process encoder, which this repository does not
ship and cannot assume. :class:`AudioTranscoder` is therefore a port with
two adapters:

* :class:`DisabledAudioTranscoder` — the DEFAULT. Rejects every audio
  upload with ``audio_transcoder_unavailable``. The composer's audio path
  is closed until an operator configures a transcoder.
* :class:`FfmpegAudioTranscoder` — decodes and re-encodes through an
  ``ffmpeg`` binary the operator points at, producing a fresh, bounded
  ``audio/mp4`` (AAC) file with all container metadata stripped
  (``-map_metadata -1``). Chosen only when
  ``STRUMSIGHT_MEDIA_AUDIO_TRANSCODER=ffmpeg``.

The fail-closed default is the same discipline as the scanner: an
unconfigured deploy stores nothing rather than storing something it never
inspected.
"""

from __future__ import annotations

import abc
import io
import shutil
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Final

from PIL import Image, UnidentifiedImageError

from .sniff import (
    MEDIA_TYPE_JPEG,
    MEDIA_TYPE_MP4,
    MEDIA_TYPE_WEBP,
)

#: Rejection code when the image cannot be decoded by Pillow (a
#: signature match is not a guarantee the rest of the file is an image).
REJECT_IMAGE_UNREADABLE: Final[str] = "image_unreadable"
#: Rejection code when the operator has not configured an audio encoder.
REJECT_AUDIO_UNAVAILABLE: Final[str] = "audio_transcoder_unavailable"
#: Rejection code when the configured audio encoder refused the input.
REJECT_AUDIO_UNREADABLE: Final[str] = "audio_unreadable"
#: Rejection code when the decoded audio is longer than the cap.
REJECT_AUDIO_TOO_LONG: Final[str] = "audio_too_long"


class TranscodeError(Exception):
    """A re-encode refused the input. ``code`` is the rejection code."""

    def __init__(self, code: str) -> None:
        super().__init__(code)
        self.code = code


@dataclass(frozen=True)
class TranscodedMedia:
    """The re-encoded artefact the store will persist."""

    data: bytes
    media_type: str
    width: int | None = None
    height: int | None = None
    duration_ms: int | None = None


class ImageTranscoder(abc.ABC):
    """Port for the image re-encode."""

    @abc.abstractmethod
    def transcode(self, data: bytes) -> TranscodedMedia:
        """Return the re-encoded image, or raise :class:`TranscodeError`."""


class PillowImageTranscoder(ImageTranscoder):
    """Decode-and-re-encode through Pillow.

    ``max_dimension`` bounds the LONGEST edge of the output; the aspect
    ratio is preserved. ``quality`` is the JPEG/WebP quality factor.
    """

    def __init__(self, *, max_dimension: int = 2048, quality: int = 82) -> None:
        self._max_dimension = max(1, int(max_dimension))
        self._quality = max(1, min(100, int(quality)))

    def transcode(self, data: bytes) -> TranscodedMedia:
        try:
            with Image.open(io.BytesIO(data)) as probe:
                # ``verify`` walks the file's structure and raises on a
                # truncated / lying container. The image object is
                # unusable afterwards, hence the second open below.
                probe.verify()
            with Image.open(io.BytesIO(data)) as image:
                image.load()
                frames = getattr(image, "n_frames", 1)
                has_alpha = image.mode in ("RGBA", "LA", "PA") or (
                    image.mode == "P" and "transparency" in image.info
                )
                target = image.convert("RGBA" if has_alpha else "RGB")
        except (UnidentifiedImageError, OSError, ValueError, SyntaxError) as exc:
            # Includes Pillow's DecompressionBombError (a ValueError
            # subclass) and every truncated-file OSError.
            raise TranscodeError(REJECT_IMAGE_UNREADABLE) from exc

        if frames and frames > 1:
            # Animated input (GIF/APNG/animated WebP): only the first
            # frame survives, which is what ``convert`` already produced.
            # Nothing else to do — the note exists so the behaviour is a
            # decision, not an accident.
            pass

        target.thumbnail(
            (self._max_dimension, self._max_dimension),
            Image.LANCZOS,
        )
        buffer = io.BytesIO()
        if has_alpha:
            target.save(buffer, format="WEBP", quality=self._quality, method=4)
            media_type = MEDIA_TYPE_WEBP
        else:
            target.save(
                buffer,
                format="JPEG",
                quality=self._quality,
                optimize=True,
                # No `exif=` argument: the metadata is dropped by
                # construction, and passing the source EXIF back would
                # undo the point of this module.
            )
            media_type = MEDIA_TYPE_JPEG
        width, height = target.size
        target.close()
        return TranscodedMedia(
            data=buffer.getvalue(),
            media_type=media_type,
            width=width,
            height=height,
        )


class AudioTranscoder(abc.ABC):
    """Port for the audio re-encode."""

    #: Short adapter name persisted for the audit trail.
    name: str = "audio"

    @abc.abstractmethod
    def transcode(self, data: bytes, *, media_type: str) -> TranscodedMedia:
        """Return the re-encoded audio, or raise :class:`TranscodeError`."""


class DisabledAudioTranscoder(AudioTranscoder):
    """The fail-closed default — audio uploads are rejected.

    The state machine still runs to completion; the upload simply lands
    in ``rejected`` with ``audio_transcoder_unavailable``, which the
    client renders through its existing rejected face.
    """

    name = "disabled"

    def transcode(self, data: bytes, *, media_type: str) -> TranscodedMedia:
        raise TranscodeError(REJECT_AUDIO_UNAVAILABLE)


class FfmpegAudioTranscoder(AudioTranscoder):
    """Re-encode through an operator-provided ``ffmpeg`` binary.

    The invocation is deliberately narrow:

    * ``-map_metadata -1`` drops every container tag (ID3, iTunes atoms)
      — the audio equivalent of the image EXIF strip.
    * ``-vn`` drops any video / cover-art stream, so an ``.m4a`` with an
      embedded video track cannot smuggle one through.
    * ``-t <cap>`` truncates at the duration cap instead of trusting the
      container's declared duration.
    * input and output are real temp FILES, never a shell string — the
      argument vector is passed to ``subprocess.run`` without a shell, so
      a filename can never be interpreted.
    """

    name = "ffmpeg"

    def __init__(
        self,
        *,
        ffmpeg_path: str = "ffmpeg",
        max_duration_seconds: int = 180,
        timeout_seconds: float = 60.0,
    ) -> None:
        self._ffmpeg = ffmpeg_path
        self._max_duration = max(1, int(max_duration_seconds))
        self._timeout = timeout_seconds

    def transcode(self, data: bytes, *, media_type: str) -> TranscodedMedia:
        binary = shutil.which(self._ffmpeg) or self._ffmpeg
        with tempfile.TemporaryDirectory(prefix="ss-audio-") as tmp:
            source = Path(tmp) / "in.bin"
            target = Path(tmp) / "out.m4a"
            source.write_bytes(data)
            command = [
                binary,
                "-nostdin",
                "-hide_banner",
                "-loglevel",
                "error",
                "-i",
                str(source),
                "-vn",
                "-map_metadata",
                "-1",
                "-t",
                str(self._max_duration),
                "-c:a",
                "aac",
                "-b:a",
                "128k",
                "-movflags",
                "+faststart",
                "-y",
                str(target),
            ]
            try:
                completed = subprocess.run(  # noqa: S603 - fixed argv, no shell
                    command,
                    capture_output=True,
                    timeout=self._timeout,
                    check=False,
                )
            except (OSError, subprocess.TimeoutExpired) as exc:
                raise TranscodeError(REJECT_AUDIO_UNAVAILABLE) from exc
            if completed.returncode != 0 or not target.exists():
                raise TranscodeError(REJECT_AUDIO_UNREADABLE)
            encoded = target.read_bytes()
        if not encoded:
            raise TranscodeError(REJECT_AUDIO_UNREADABLE)
        return TranscodedMedia(data=encoded, media_type=MEDIA_TYPE_MP4)


def build_image_transcoder(settings) -> ImageTranscoder:
    """The image adapter is always Pillow — there is no disabled variant.

    Unlike audio, the image encoder ships with the backend, so "no image
    transcoder" is not a reachable configuration; making it one would
    only create a way to accidentally store un-re-encoded bytes.
    """
    return PillowImageTranscoder(
        max_dimension=settings.media_image_max_dimension,
        quality=settings.media_image_quality,
    )


def build_audio_transcoder(settings) -> AudioTranscoder:
    """Select the audio adapter; anything unrecognised is *disabled*."""
    raw = getattr(settings, "media_audio_transcoder", "") or ""
    selected = raw.strip().lower()
    if selected == "ffmpeg":
        return FfmpegAudioTranscoder(
            ffmpeg_path=settings.media_ffmpeg_path,
            max_duration_seconds=settings.media_audio_max_duration_seconds,
        )
    return DisabledAudioTranscoder()


__all__ = [
    "REJECT_AUDIO_TOO_LONG",
    "REJECT_AUDIO_UNAVAILABLE",
    "REJECT_AUDIO_UNREADABLE",
    "REJECT_IMAGE_UNREADABLE",
    "AudioTranscoder",
    "DisabledAudioTranscoder",
    "FfmpegAudioTranscoder",
    "ImageTranscoder",
    "PillowImageTranscoder",
    "TranscodeError",
    "TranscodedMedia",
    "build_audio_transcoder",
    "build_image_transcoder",
]
