"""Idempotent installer for the shared Codex MiniMax/Terra profiles."""

from __future__ import annotations

import json
import os
import shutil
import tempfile
from dataclasses import dataclass
from pathlib import Path

from .credential import read_minimax_api_key


BEGIN_MARKER = "# BEGIN STRUMSIGHT MINIMAX ROUTER (managed)"
END_MARKER = "# END STRUMSIGHT MINIMAX ROUTER (managed)"


class InstallError(RuntimeError):
    pass


@dataclass(frozen=True)
class InstallReport:
    changed: bool
    installed_paths: tuple[str, ...]

    def to_dict(self) -> dict[str, object]:
        return {"changed": self.changed, "installed_paths": list(self.installed_paths)}


def _atomic_write(path: Path, content: bytes, mode: int) -> bool:
    if path.exists() and path.read_bytes() == content and (path.stat().st_mode & 0o777) == mode:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=path.name + ".", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    except BaseException:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise
    return True


def _managed_provider_block(helper: Path) -> str:
    command = json.dumps(os.fspath(helper), ensure_ascii=False)
    return (
        f"{BEGIN_MARKER}\n"
        "[model_providers.minimax]\n"
        'name = "MiniMax"\n'
        'base_url = "https://api.minimax.io/v1"\n'
        'wire_api = "responses"\n'
        "request_max_retries = 2\n"
        "stream_max_retries = 2\n\n"
        "[model_providers.minimax.auth]\n"
        f"command = {command}\n"
        "timeout_ms = 5000\n"
        "refresh_interval_ms = 0\n"
        f"{END_MARKER}"
    )


def _merge_provider(existing: str, block: str) -> str:
    has_begin = BEGIN_MARKER in existing
    has_end = END_MARKER in existing
    if has_begin != has_end:
        raise InstallError("managed MiniMax provider markers are incomplete")
    if has_begin:
        before, remainder = existing.split(BEGIN_MARKER, 1)
        _, after = remainder.split(END_MARKER, 1)
        return f"{before}{block}{after}"
    if "[model_providers.minimax]" in existing or "[model_providers.minimax.auth]" in existing:
        raise InstallError("an unmanaged model_providers.minimax block already exists")
    separator = "" if not existing else ("\n" if existing.endswith("\n") else "\n\n")
    return f"{existing}{separator}{block}\n"


M3_PROFILE = """model = "MiniMax-M3"
model_provider = "minimax"
model_context_window = 1000000
model_reasoning_effort = "high"
model_reasoning_summary = "none"
approval_policy = "on-request"
sandbox_mode = "workspace-write"
"""

TERRA_PROFILE = """model = "gpt-5.6-terra"
model_provider = "openai"
model_reasoning_effort = "medium"
model_verbosity = "low"
model_reasoning_summary = "none"
approval_policy = "on-request"
sandbox_mode = "workspace-write"
"""


def install_router(*, home: Path, repo_root: Path, source_config: Path) -> InstallReport:
    read_minimax_api_key(source_config)
    codex_dir = home / ".codex"
    libexec = home / ".local" / "libexec" / "strumsight-ai"
    runtime = libexec / "ai_router"
    state_dir = home / ".local" / "state" / "strumsight-ai-router"
    for directory in (codex_dir, libexec, runtime, state_dir):
        directory.mkdir(parents=True, exist_ok=True)
        directory.chmod(0o700)

    sources = {
        libexec / "minimax-credential": repo_root / "tools" / "minimax-credential.py",
        libexec / "minimax-quota": repo_root / "tools" / "minimax-quota.py",
        runtime / "credential.py": repo_root / "tools" / "ai_router" / "credential.py",
        runtime / "quota.py": repo_root / "tools" / "ai_router" / "quota.py",
    }
    changed = False
    installed: list[str] = []
    for destination, source in sources.items():
        if not source.is_file():
            raise InstallError(f"installer source is missing: {source}")
        mode = 0o700 if destination.parent == libexec else 0o600
        changed |= _atomic_write(destination, source.read_bytes(), mode)
        installed.append(os.fspath(destination))

    init_file = runtime / "__init__.py"
    changed |= _atomic_write(init_file, b'"""Installed StrumSight AI helpers."""\n', 0o600)
    installed.append(os.fspath(init_file))

    config_path = codex_dir / "config.toml"
    existing = config_path.read_text(encoding="utf-8") if config_path.exists() else ""
    merged = _merge_provider(existing, _managed_provider_block(libexec / "minimax-credential"))
    if merged != existing and config_path.exists():
        backup = codex_dir / "config.toml.pre-minimax-router.bak"
        if not backup.exists():
            _atomic_write(backup, existing.encode(), 0o600)
            installed.append(os.fspath(backup))
    changed |= _atomic_write(config_path, merged.encode(), 0o600)
    installed.append(os.fspath(config_path))

    profiles = {
        codex_dir / "m3.config.toml": M3_PROFILE,
        codex_dir / "terra.config.toml": TERRA_PROFILE,
    }
    for path, content in profiles.items():
        changed |= _atomic_write(path, content.encode(), 0o600)
        installed.append(os.fspath(path))
    return InstallReport(changed, tuple(installed))
