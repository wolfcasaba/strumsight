"""Community media upload pipeline (javító sáv R27).

The package that closes the three open items of
``docs/security/community-threat-model.md`` §6.2:

* **A6.2.1 — magic-byte validation.** :mod:`.sniff` decides what a byte
  string IS. Neither the filename extension nor the multipart
  ``Content-Type`` header participates in that decision; both are
  caller-supplied and therefore unusable as a security input.
* **A6.2.4 — transcode / re-encode.** :mod:`.transcode` re-encodes every
  accepted image through Pillow into a fresh JPEG/WebP at bounded
  dimensions, so the stored bytes are the encoder's output, not the
  uploader's container (EXIF, trailing payloads and polyglot tails do not
  survive). Audio has a pluggable transcoder whose DEFAULT REJECTS.
* **A6.2.5 — a real scanner.** :mod:`.scanner` ships a clamd INSTREAM
  adapter and a *disabled* adapter that REJECTS. There is deliberately no
  pass-through adapter: an unconfigured deploy refuses uploads rather than
  storing unscanned bytes.

:mod:`.store` is the content-addressed filesystem store, :mod:`.pipeline`
is the state machine (``pending → scanning → transcoding → review? →
ready | rejected``) tying the four together, and
``routers/media.py`` is the HTTP surface.

The whole package is dead weight unless ``Settings.community_media_enabled``
is true: ``build_community_router`` does not register the router otherwise,
so the endpoints do not exist (registration-level gate, ADR 0497 D1) and
the client's existing graceful 404 path handles it.
"""

from __future__ import annotations

__all__: list[str] = []
