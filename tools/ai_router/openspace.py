"""Launch OpenSpace MCP with a private runtime-only MiniMax credential."""

from __future__ import annotations

import os
import sys
from pathlib import Path
from typing import Mapping

from .credential import CredentialError, read_minimax_api_key


DEFAULT_OPENSPACE_EXECUTABLE = Path("/opt/OpenSpace/venv/bin/openspace-mcp")


def build_openspace_environment(
    source_config: Path, parent: Mapping[str, str]
) -> dict[str, str]:
    environment = dict(parent)
    environment["OPENAI_API_KEY"] = read_minimax_api_key(source_config)
    return environment


def main() -> int:
    source = Path.home() / ".mmx" / "config.json"
    try:
        environment = build_openspace_environment(source, os.environ)
        target = DEFAULT_OPENSPACE_EXECUTABLE
        os.execve(os.fspath(target), [os.fspath(target), *sys.argv[1:]], environment)
    except CredentialError as error:
        print(f"openspace credential unavailable: {error}", file=sys.stderr)
    except OSError as error:
        print(f"openspace executable unavailable: {error.__class__.__name__}", file=sys.stderr)
    return 1
