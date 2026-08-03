"""Fail-closed versioned TOML router configuration."""

from __future__ import annotations

import sys
import tomllib
from pathlib import Path
from typing import Any

from .models import LimitsConfig, RouterConfig, RoutingConfig, RuntimeConfig, SecurityConfig


class ConfigError(ValueError):
    pass


ROOT_KEYS = {"schema_version", "routing", "limits", "runtime", "security"}
ROUTING_KEYS = {"default_engine", "default_provider", "default_model"}
LIMIT_KEYS = {
    "max_m3_attempts_per_task",
    "max_terra_calls_per_task",
    "max_automatic_terra_calls_per_utc_day",
    "terra_reasoning",
    "terra_packet_target_tokens",
    "terra_packet_max_bytes",
}
RUNTIME_KEYS = {
    "state_dir",
    "quota_helper",
    "gate_script",
    "codex_bin",
    "m3_profile",
    "terra_profile",
    "model_timeout_seconds",
    "gate_timeout_seconds",
}
SECURITY_KEYS = {"protected_paths", "high_risk_path_fragments", "native_gate_command"}


def _table(value: object, name: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ConfigError(f"{name} must be a TOML table")
    return value


def _exact_keys(table: dict[str, Any], expected: set[str], name: str) -> None:
    unknown = set(table) - expected
    missing = expected - set(table)
    if unknown:
        raise ConfigError(f"unknown {name} key(s): {', '.join(sorted(unknown))}")
    if missing:
        raise ConfigError(f"missing {name} key(s): {', '.join(sorted(missing))}")


def _string(table: dict[str, Any], key: str) -> str:
    value = table[key]
    if not isinstance(value, str) or not value.strip() or "\x00" in value:
        raise ConfigError(f"{key} must be a non-empty string")
    return value


def _integer(table: dict[str, Any], key: str, *, minimum: int = 1) -> int:
    value = table[key]
    if isinstance(value, bool) or not isinstance(value, int) or value < minimum:
        raise ConfigError(f"{key} must be an integer >= {minimum}")
    return value


def _strings(table: dict[str, Any], key: str) -> tuple[str, ...]:
    value = table[key]
    if not isinstance(value, list) or not value:
        raise ConfigError(f"{key} must be a non-empty string array")
    result = tuple(value)
    if any(not isinstance(item, str) or not item.strip() or "\x00" in item for item in result):
        raise ConfigError(f"{key} must contain non-empty strings")
    if len(set(result)) != len(result):
        raise ConfigError(f"{key} must not contain duplicates")
    return result


def load_config(path: Path) -> RouterConfig:
    if sys.version_info < (3, 11):
        raise ConfigError("Python 3.11 or newer is required")
    try:
        data = tomllib.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, tomllib.TOMLDecodeError) as error:
        raise ConfigError(f"router config is unreadable: {path}") from error
    _exact_keys(data, ROOT_KEYS, "root")
    if data["schema_version"] != 1 or isinstance(data["schema_version"], bool):
        raise ConfigError("unsupported schema_version")
    routing = _table(data["routing"], "routing")
    limits = _table(data["limits"], "limits")
    runtime = _table(data["runtime"], "runtime")
    security = _table(data["security"], "security")
    _exact_keys(routing, ROUTING_KEYS, "routing")
    _exact_keys(limits, LIMIT_KEYS, "limits")
    _exact_keys(runtime, RUNTIME_KEYS, "runtime")
    _exact_keys(security, SECURITY_KEYS, "security")
    if _string(routing, "default_engine") != "auto":
        raise ConfigError("default_engine must be auto")
    if _string(routing, "default_provider") != "minimax":
        raise ConfigError("default_provider must be minimax")
    if _integer(limits, "max_m3_attempts_per_task") != 2:
        raise ConfigError("max_m3_attempts_per_task must be exactly 2")
    if _integer(limits, "max_terra_calls_per_task") != 2:
        raise ConfigError("max_terra_calls_per_task must be exactly 2")
    if _string(limits, "terra_reasoning") != "medium":
        raise ConfigError("terra_reasoning must be medium")
    return RouterConfig(
        schema_version=1,
        routing=RoutingConfig(
            default_engine="auto",
            default_provider="minimax",
            default_model=_string(routing, "default_model"),
        ),
        limits=LimitsConfig(
            max_m3_attempts_per_task=2,
            max_terra_calls_per_task=2,
            max_automatic_terra_calls_per_utc_day=_integer(
                limits, "max_automatic_terra_calls_per_utc_day", minimum=0
            ),
            terra_reasoning="medium",
            terra_packet_target_tokens=_integer(limits, "terra_packet_target_tokens"),
            terra_packet_max_bytes=_integer(limits, "terra_packet_max_bytes"),
        ),
        runtime=RuntimeConfig(
            state_dir=_string(runtime, "state_dir"),
            quota_helper=_string(runtime, "quota_helper"),
            gate_script=_string(runtime, "gate_script"),
            codex_bin=_string(runtime, "codex_bin"),
            m3_profile=_string(runtime, "m3_profile"),
            terra_profile=_string(runtime, "terra_profile"),
            model_timeout_seconds=_integer(runtime, "model_timeout_seconds"),
            gate_timeout_seconds=_integer(runtime, "gate_timeout_seconds"),
        ),
        security=SecurityConfig(
            protected_paths=_strings(security, "protected_paths"),
            high_risk_path_fragments=_strings(security, "high_risk_path_fragments"),
            native_gate_command=_strings(security, "native_gate_command"),
        ),
    )
