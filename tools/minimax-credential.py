#!/usr/bin/env python3
"""Codex command-backed auth helper. Stdout is intentionally token-only."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from ai_router.credential import CredentialError, read_minimax_api_key


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--source-config", type=Path, default=Path.home() / ".mmx" / "config.json"
    )
    args = parser.parse_args()
    try:
        token = read_minimax_api_key(args.source_config)
    except CredentialError as error:
        print(f"minimax credential unavailable: {error}", file=sys.stderr)
        return 1
    print(token)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
