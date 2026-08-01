#!/usr/bin/env python3
"""Return a small sanitized MiniMax quota status document."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from ai_router.credential import CredentialError, read_minimax_api_key
from ai_router.quota import QuotaStatus, check_quota


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check-only", action="store_true")
    parser.add_argument(
        "--source-config", type=Path, default=Path.home() / ".mmx" / "config.json"
    )
    args = parser.parse_args()
    try:
        token = read_minimax_api_key(args.source_config)
        result = check_quota(token)
    except CredentialError:
        result = QuotaStatus("credential_blocked", False, False)
    print(json.dumps(result.to_dict(), ensure_ascii=False, sort_keys=True))
    return 0 if result.status == "ok" and result.quota_known else 3


if __name__ == "__main__":
    raise SystemExit(main())
