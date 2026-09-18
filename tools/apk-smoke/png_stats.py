#!/usr/bin/env python3
"""Stdlib-only PNG inspector for the APK smoke evidence.

`adb exec-out screencap -p` writes a plain 8-bit PNG. This helper decodes it
with nothing but `zlib` + `struct` (no Pillow, no ImageMagick on the runner)
and answers the single question the smoke needs: *is the screenshot a real
frame, or a uniformly blank/black surface?*

Output: one JSON object on stdout.
Exit code: 0 when every requested threshold holds, 1 otherwise (so the shell
can use the call directly as an assertion), 2 on an unreadable file.

A file whose PNG flavour we cannot decode (16-bit, interlaced, palette) is NOT
failed on colour grounds — only the byte-size threshold applies, and
`"decoded": false` is reported so the evidence stays honest.
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
import zlib

PNG_MAGIC = b"\x89PNG\r\n\x1a\n"
# Channel count per PNG colour type (2 = truecolour, 6 = truecolour+alpha).
CHANNELS = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}


def _read_chunks(blob: bytes):
    """Yield (type, data) for every chunk in the PNG byte string."""
    offset = 8
    while offset + 8 <= len(blob):
        (length,) = struct.unpack(">I", blob[offset : offset + 4])
        ctype = blob[offset + 4 : offset + 8]
        data = blob[offset + 8 : offset + 8 + length]
        yield ctype, data
        offset += 12 + length  # length + type + data + crc


def _paeth(a: int, b: int, c: int) -> int:
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    if pb <= pc:
        return b
    return c


def _unfilter(raw: bytes, width: int, height: int, channels: int) -> bytearray:
    """Undo the per-scanline PNG filters; returns the raw pixel bytes."""
    stride = width * channels
    out = bytearray(stride * height)
    prev = bytearray(stride)
    pos = 0
    for row in range(height):
        ftype = raw[pos]
        pos += 1
        line = bytearray(raw[pos : pos + stride])
        pos += stride
        if ftype == 0:
            pass
        elif ftype == 1:  # Sub
            for i in range(channels, stride):
                line[i] = (line[i] + line[i - channels]) & 0xFF
        elif ftype == 2:  # Up
            line = bytearray((x + y) & 0xFF for x, y in zip(line, prev))
        elif ftype == 3:  # Average
            for i in range(stride):
                left = line[i - channels] if i >= channels else 0
                line[i] = (line[i] + ((left + prev[i]) >> 1)) & 0xFF
        elif ftype == 4:  # Paeth
            for i in range(stride):
                left = line[i - channels] if i >= channels else 0
                upleft = prev[i - channels] if i >= channels else 0
                line[i] = (line[i] + _paeth(left, prev[i], upleft)) & 0xFF
        else:
            raise ValueError(f"unknown PNG filter type {ftype} on row {row}")
        out[row * stride : (row + 1) * stride] = line
        prev = line
    return out


def _decode(blob: bytes):
    """Return (width, height, channels, pixels) or None when unsupported."""
    if not blob.startswith(PNG_MAGIC):
        raise ValueError("not a PNG file")
    header = None
    idat = bytearray()
    for ctype, data in _read_chunks(blob):
        if ctype == b"IHDR":
            header = struct.unpack(">IIBBBBB", data[:13])
        elif ctype == b"IDAT":
            idat += data
        elif ctype == b"IEND":
            break
    if header is None:
        raise ValueError("PNG without IHDR")
    width, height, depth, colour, _compression, _filter, interlace = header
    if depth != 8 or interlace != 0 or colour not in (0, 2, 4, 6):
        return None  # a flavour this stdlib decoder deliberately skips
    channels = CHANNELS[colour]
    raw = zlib.decompress(bytes(idat))
    if len(raw) < height * (1 + width * channels):
        raise ValueError("truncated PNG image data")
    return width, height, channels, _unfilter(raw, width, height, channels)


def _stats(width, height, channels, pixels, sample_step):
    """Colour histogram over a subsample of the pixels (RGB triplets)."""
    stride = width * channels
    histogram: dict[tuple[int, int, int], int] = {}
    non_black = 0
    counted = 0
    for y in range(0, height, sample_step):
        base = y * stride
        for x in range(0, width, sample_step):
            off = base + x * channels
            if channels >= 3:
                rgb = (pixels[off], pixels[off + 1], pixels[off + 2])
            else:
                grey = pixels[off]
                rgb = (grey, grey, grey)
            histogram[rgb] = histogram.get(rgb, 0) + 1
            counted += 1
            if max(rgb) > 12:  # tolerate near-black anti-aliasing noise
                non_black += 1
    dominant = max(histogram.values()) if histogram else 0
    return {
        "sampled_pixels": counted,
        "unique_colors": len(histogram),
        "dominant_color_ratio": round(dominant / counted, 4) if counted else 1.0,
        "non_black_ratio": round(non_black / counted, 4) if counted else 0.0,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="PNG evidence inspector")
    parser.add_argument("path")
    parser.add_argument("--min-bytes", type=int, default=0)
    parser.add_argument("--min-colors", type=int, default=0)
    parser.add_argument(
        "--min-non-black",
        type=float,
        default=0.0,
        help="minimum fraction of sampled pixels brighter than near-black",
    )
    parser.add_argument("--sample-step", type=int, default=4)
    args = parser.parse_args()

    try:
        with open(args.path, "rb") as handle:
            blob = handle.read()
    except OSError as error:
        print(json.dumps({"path": args.path, "error": str(error)}))
        return 2

    result: dict[str, object] = {
        "path": args.path,
        "bytes": len(blob),
        "decoded": False,
    }
    try:
        decoded = _decode(blob)
    except Exception as error:  # corrupt capture is evidence, not a crash
        result["error"] = f"{type(error).__name__}: {error}"
        decoded = None
    if decoded is not None:
        width, height, channels, pixels = decoded
        result.update(
            {
                "decoded": True,
                "width": width,
                "height": height,
                "channels": channels,
            }
        )
        result.update(_stats(width, height, channels, pixels, max(1, args.sample_step)))

    failures = []
    if len(blob) < args.min_bytes:
        failures.append(f"bytes {len(blob)} < {args.min_bytes}")
    if result["decoded"]:
        if int(result["unique_colors"]) < args.min_colors:
            failures.append(f"unique_colors {result['unique_colors']} < {args.min_colors}")
        if float(result["non_black_ratio"]) < args.min_non_black:
            failures.append(
                f"non_black_ratio {result['non_black_ratio']} < {args.min_non_black}"
            )
    result["failures"] = failures
    result["ok"] = not failures
    print(json.dumps(result))
    return 0 if not failures else 1


if __name__ == "__main__":
    sys.exit(main())
