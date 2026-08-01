"""Idempotent installer for the shared Codex MiniMax/Terra profiles."""

from __future__ import annotations

import json
import os
import tempfile
import tomllib
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


def _migrate_openspace_secret(existing: str, api_key: str, wrapper: Path) -> str:
    """Remove a legacy literal MiniMax key without changing other MCP settings."""
    try:
        parsed = tomllib.loads(existing)
    except tomllib.TOMLDecodeError as error:
        raise InstallError("existing Codex config is not valid TOML") from error
    servers = parsed.get("mcp_servers")
    server = servers.get("openspace-vm") if isinstance(servers, dict) else None
    environment = server.get("env") if isinstance(server, dict) else None
    if not isinstance(environment, dict) or environment.get("OPENAI_API_KEY") != api_key:
        return existing
    if server.get("command") not in (
        "/opt/OpenSpace/venv/bin/openspace-mcp",
        os.fspath(wrapper),
    ):
        raise InstallError("cannot migrate the OpenSpace credential from an unknown command")
    if not all(
        isinstance(key, str) and isinstance(value, str)
        for key, value in environment.items()
    ):
        raise InstallError("OpenSpace environment must contain only string values")

    lines = existing.splitlines(keepends=True)
    headers = {'[mcp_servers."openspace-vm"]', "[mcp_servers.openspace-vm]"}
    table = [index for index, line in enumerate(lines) if line.strip() in headers]
    if len(table) != 1:
        raise InstallError("cannot locate the OpenSpace MCP table uniquely")
    start = table[0] + 1
    end = next(
        (index for index in range(start, len(lines)) if lines[index].lstrip().startswith("[")),
        len(lines),
    )

    def assignment(name: str) -> int:
        matches = []
        for index in range(start, end):
            line = lines[index]
            if line.lstrip().startswith("#") or "=" not in line:
                continue
            if line.split("=", 1)[0].strip() == name:
                matches.append(index)
        if len(matches) != 1:
            raise InstallError(f"cannot locate OpenSpace {name} assignment uniquely")
        return matches[0]

    command_index = assignment("command")
    environment_index = assignment("env")
    remaining = {key: value for key, value in environment.items() if key != "OPENAI_API_KEY"}
    newline = "\r\n" if lines[environment_index].endswith("\r\n") else "\n"
    command_indent = lines[command_index][
        : len(lines[command_index]) - len(lines[command_index].lstrip())
    ]
    env_indent = lines[environment_index][
        : len(lines[environment_index]) - len(lines[environment_index].lstrip())
    ]
    inline = ", ".join(
        f"{json.dumps(key, ensure_ascii=False)} = {json.dumps(value, ensure_ascii=False)}"
        for key, value in remaining.items()
    )
    encoded_wrapper = json.dumps(os.fspath(wrapper))
    lines[command_index] = f"{command_indent}command = {encoded_wrapper}{newline}"
    lines[environment_index] = f"{env_indent}env = {{ {inline} }}{newline}"
    migrated = "".join(lines)
    expected = parsed
    expected_server = expected["mcp_servers"]["openspace-vm"]
    expected_server["command"] = os.fspath(wrapper)
    expected_server["env"] = remaining
    try:
        reparsed = tomllib.loads(migrated)
    except tomllib.TOMLDecodeError as error:
        raise InstallError("migrated Codex config is not valid TOML") from error
    if reparsed != expected:
        raise InstallError("OpenSpace credential migration changed unrelated configuration")
    return migrated


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
    minimax_key = read_minimax_api_key(source_config)
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
        libexec / "openspace-vm": repo_root / "tools" / "openspace-vm-wrapper.py",
        runtime / "credential.py": repo_root / "tools" / "ai_router" / "credential.py",
        runtime / "quota.py": repo_root / "tools" / "ai_router" / "quota.py",
        runtime / "openspace.py": repo_root / "tools" / "ai_router" / "openspace.py",
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
    sanitized = _migrate_openspace_secret(existing, minimax_key, libexec / "openspace-vm")
    merged = _merge_provider(sanitized, _managed_provider_block(libexec / "minimax-credential"))
    backup = codex_dir / "config.toml.pre-minimax-router.bak"
    if merged != existing and config_path.exists() and not backup.exists():
        changed |= _atomic_write(backup, sanitized.encode(), 0o600)
        installed.append(os.fspath(backup))
    elif backup.exists():
        backup_text = backup.read_text(encoding="utf-8")
        sanitized_backup = _migrate_openspace_secret(
            backup_text, minimax_key, libexec / "openspace-vm"
        )
        if sanitized_backup != backup_text:
            changed |= _atomic_write(backup, sanitized_backup.encode(), 0o600)
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
