"""Release security gate — backend side (E12-R18, ADR 0481, brief A9).

`tool/release/security_scan.py` measures that every `release_gate: true`
guard in `docs/security/threat-model.md` still resolves on the tree. This
file measures the OTHER direction for the backend guards specifically: that
their `guard.path` + `guard.test` pair is a pytest node id `--collect-only`
can actually resolve TODAY, and that a corrupted node id (a renamed or
deleted test slipping past a substring check) is measurably red. It reuses
`security_scan.py`'s own threat-model parser via direct module load rather
than re-implementing the ```yaml``` guard-block extraction here — a second
parser for the same document would be exactly the duplicated-source-of-truth
risk ADR 0481 §0.0 R2 warns about.
"""

from __future__ import annotations

import importlib.util
import subprocess
import sys
from pathlib import Path
from types import ModuleType

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[2]
_BACKEND_DIR = _REPO_ROOT / "backend"
_THREAT_MODEL = _REPO_ROOT / "docs" / "security" / "threat-model.md"
_SCAN_MODULE_PATH = _REPO_ROOT / "tool" / "release" / "security_scan.py"


def _load_security_scan() -> ModuleType:
    spec = importlib.util.spec_from_file_location(
        "strumsight_security_scan_e12r18", _SCAN_MODULE_PATH
    )
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    # `security_scan.py` uses `from __future__ import annotations`, so its
    # dataclasses resolve field types lazily via `sys.modules[__module__]` —
    # that lookup fails unless the module is registered before exec_module
    # runs.
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


_security_scan = _load_security_scan()


def _resolve_node_id(relative_path: str, guard_test: str) -> str:
    """Resolves the ACTUAL pytest node id for `guard_test` in
    `relative_path` — a flat `<path>::<name>` guess breaks for a guard
    living inside a `class Test...:` (e.g. T-API-02, `TestAuthThrottle`),
    whose real node id is `<path>::TestAuthThrottle::<name>`. Listing the
    file's own collected node ids and matching the `::<name>` suffix avoids
    hardcoding a class-nesting assumption."""
    # NOT `-q` here: quiet mode collapses a whole-file collection to a
    # single "<file>: <count>" summary line with no node ids at all — the
    # per-node listing this needs only appears in the default (verbose)
    # collection format.
    result = subprocess.run(
        [sys.executable, "-m", "pytest", "--collect-only", relative_path],
        cwd=_BACKEND_DIR,
        capture_output=True,
        text=True,
        timeout=60,
    )
    suffix = f"::{guard_test}"
    for line in result.stdout.splitlines():
        line = line.strip()
        if line.endswith(suffix):
            return line
    # No collected node id matched — fall back to the flat guess so the
    # guard still fails LOUDLY downstream (a missing node id, not a
    # silently vanished guard) rather than raising here and hiding which
    # guard is broken.
    return f"{relative_path}{suffix}"


def _backend_guard_node_ids() -> list[str]:
    """`backend/`-relative pytest node ids for every backend, release_gate,
    test-bearing guard in the real threat model."""
    entries, findings = _security_scan.load_threat_model(_THREAT_MODEL)
    assert not findings, f"threat model has unresolved validation findings: {findings}"

    node_ids = []
    for entry in entries:
        if not entry.release_gate or not entry.guard_test:
            continue
        if not entry.guard_path.startswith("backend/"):
            continue
        relative_path = entry.guard_path[len("backend/") :]
        node_ids.append(_resolve_node_id(relative_path, entry.guard_test))
    return node_ids


def _collect_only(node_id: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, "-m", "pytest", "--collect-only", "-q", node_id],
        cwd=_BACKEND_DIR,
        capture_output=True,
        text=True,
        timeout=60,
    )


NODE_IDS = _backend_guard_node_ids()


def test_at_least_one_backend_release_gate_guard_is_declared() -> None:
    assert NODE_IDS, (
        "expected at least one backend release_gate guard with a guard.test"
    )


@pytest.mark.parametrize("node_id", NODE_IDS)
def test_backend_guard_resolves_as_a_pytest_node_id(node_id: str) -> None:
    result = _collect_only(node_id)
    assert result.returncode == 0, (
        f"{node_id} did not collect (exit {result.returncode}):\n"
        f"{result.stdout}\n{result.stderr}"
    )
    # `pytest --collect-only -q` on a single-file node id prints
    # "<file>: <count>" rather than the "N tests collected" summary line
    # (measured: that summary only appears once collection spans the
    # session, not a single explicit node id) — the file must still be
    # named, proving pytest actually found and grouped the node.
    assert node_id.split("::", 1)[0] in result.stdout, result.stdout


def test_a_corrupted_backend_guard_node_id_fails_to_collect() -> None:
    original = NODE_IDS[0]
    path, _, test_name = original.partition("::")
    corrupted = f"{path}::{test_name}_renamed_and_no_one_noticed"

    result = _collect_only(corrupted)

    assert result.returncode != 0, (
        f"a renamed/deleted test must NOT resolve as a node id: {corrupted}\n"
        f"{result.stdout}"
    )
    assert "not found" in (result.stdout + result.stderr).lower()
