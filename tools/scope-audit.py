#!/usr/bin/env python3
"""Legacy-path scope audit CLI (ADR 0138).

    tools/scope-audit.py --repo <munkapéldány> --brief <brief> --base <sha>

Reads `allowed_paths` from the brief's `ai-router` block and `protected_paths`
from `.ai/router.toml`, then reports every path the legacy implementer touched
outside that scope.  `tools/codex-round.sh` and `tools/mm-round.sh` call it
after the model exits and mirror the verdict into `.codex-round-status`, so the
orchestrator sees a machine verdict before it reads a single line of the log.

Exit codes:
    0 = in scope
    1 = scope violation (the orchestrator must NOT merge)
    2 = usage or parse error (the audit did not run — treat as unproven)
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from tools.ai_router.brief import BriefMetadataError, load_brief  # noqa: E402
from tools.ai_router.config import ConfigError, load_config  # noqa: E402
from tools.ai_router.legacy_scope import audit_legacy_scope  # noqa: E402
from tools.ai_router.security import SecurityError  # noqa: E402


def _kv_escape(value: str) -> str:
    """Collapse a value to a single safe line for the KEY=VALUE status file."""
    return " ".join(value.split())[:500]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Legacy implementer scope audit")
    parser.add_argument("--repo", required=True, type=Path, help="work copy to audit")
    parser.add_argument("--brief", required=True, type=Path, help="round brief with the ai-router block")
    parser.add_argument("--base", required=True, help="commit the implementer started from")
    parser.add_argument(
        "--config",
        type=Path,
        default=None,
        help="router config with [security].protected_paths (default: <repo>/.ai/router.toml)",
    )
    parser.add_argument("--kv", action="store_true", help="also print KEY=VALUE lines for the status file")
    arguments = parser.parse_args(argv)

    repo = arguments.repo.resolve()
    brief_path = arguments.brief
    if not brief_path.is_absolute():
        brief_path = repo / brief_path
    config_path = arguments.config or (repo / ".ai" / "router.toml")

    try:
        allowed = load_brief(brief_path).metadata.allowed_paths
    except BriefMetadataError as error:
        print(f"scope-audit: brief is unusable: {error}", file=sys.stderr)
        return 2
    try:
        protected = load_config(config_path).security.protected_paths
    except (ConfigError, OSError) as error:
        print(f"scope-audit: router config is unusable: {error}", file=sys.stderr)
        return 2

    try:
        audit = audit_legacy_scope(
            repo,
            base=arguments.base,
            allowed_paths=allowed,
            protected_paths=protected,
        )
    except SecurityError as error:
        print(f"scope-audit: audit could not run: {error}", file=sys.stderr)
        return 2

    print(audit.format())
    if arguments.kv:
        print(f"scope_audit={'ok' if audit.ok else 'VIOLATION'}")
        print(f"scope_audit_base={audit.base}")
        print(f"scope_audit_changed={len(audit.changed_paths)}")
        if not audit.ok:
            print(f"scope_audit_violations={_kv_escape('; '.join(audit.violations))}")
    return 0 if audit.ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
