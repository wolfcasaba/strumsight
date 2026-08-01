#!/usr/bin/env python3
"""Install the versioned router helpers and Codex profiles for one user."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from ai_router.credential import CredentialError
from ai_router.install import InstallError, install_router


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--home", type=Path, default=Path.home())
    parser.add_argument("--source-config", type=Path)
    args = parser.parse_args()
    source = args.source_config or args.home / ".mmx" / "config.json"
    try:
        report = install_router(
            home=args.home,
            repo_root=Path(__file__).resolve().parents[1],
            source_config=source,
        )
    except (CredentialError, InstallError, OSError) as error:
        print(f"install-ai-router: {error}", file=sys.stderr)
        return 1
    print(json.dumps(report.to_dict(), ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
