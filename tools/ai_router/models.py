"""Immutable public data contracts for the AI router."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class RoutingConfig:
    default_engine: str
    default_provider: str
    default_model: str


@dataclass(frozen=True)
class LimitsConfig:
    max_m3_attempts_per_task: int
    max_terra_calls_per_task: int
    max_automatic_terra_calls_per_utc_day: int
    terra_reasoning: str
    terra_packet_target_tokens: int
    terra_packet_max_bytes: int


@dataclass(frozen=True)
class RuntimeConfig:
    state_dir: str
    quota_helper: str
    gate_script: str
    codex_bin: str
    m3_profile: str
    terra_profile: str
    model_timeout_seconds: int
    gate_timeout_seconds: int


@dataclass(frozen=True)
class SecurityConfig:
    protected_paths: tuple[str, ...]
    high_risk_path_fragments: tuple[str, ...]
    native_gate_command: tuple[str, ...]


@dataclass(frozen=True)
class RouterConfig:
    schema_version: int
    routing: RoutingConfig
    limits: LimitsConfig
    runtime: RuntimeConfig
    security: SecurityConfig


@dataclass(frozen=True)
class BriefMetadata:
    schema_version: int
    risk: str
    allowed_paths: tuple[str, ...]
    gate_tests: tuple[str, ...]
    native_gate: bool


@dataclass(frozen=True)
class TaskBrief:
    task_id: str
    path: Path | None
    text: str
    metadata: BriefMetadata
    metadata_hash: str
