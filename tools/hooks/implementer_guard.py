#!/usr/bin/env python3
"""Implementer-oldali gépi őrök a claude-harness körökhöz (ADR 0309).

A `.claude/hooks/protect_factory_files.py` a MÉRCÉT védi minden session ellen.
Ez a hook a KÖR-SZERZŐDÉST védi, és kizárólag implementer-körben fut: a
`tools/mm-round.sh` a `--settings tools/implementer-settings.json` kapcsolóval
tölti be, és a `STRUMSIGHT_ROUND_BRIEF` környezeti változóval kapcsolja be.
Orchesztrátor- és interaktív sessionben nem is töltődik be, és a változó
hiányában akkor is teljes no-op lenne.

MIÉRT hook és nem prompt-szöveg: a claude-harness implementerek (MiniMax M3,
Sonnet) mért hibáiból három szövegesen MÁR tiltva volt, és mégis megtörtént:

* listán kívüli fájl létrehozása (mérve két külön körben, mindkettő javító
  körré vált — docs/LESSONS.md);
* a gate `| tail` mögé rejtése (E02-R07: háromszor, pedig a brief és a javító
  prompt is szó szerint tiltotta);
* lezáró jelzés nélküli kilépés (`H-NOSIGNAL`: 18 önjavító kör, és a lánc két
  valaha mért self-heal-kimerülése MINDKETTŐ ez volt — egyikük 42 órás állás).

A szöveges tiltás nem tartott. Ez a réteg gépi.

| esemény | mit tesz | hiba esetén |
|---|---|---|
| `PreToolUse` Edit/Write/NotebookEdit | a kör `allowed_paths` listáján kívüli írás blokkolva | **fail-closed** |
| `PreToolUse` Bash | a MÉRT tiltott parancsalakok blokkolva | fail-open |
| `PostToolUse` Edit/Write `.dart` | `dart format` a fájlra | fail-open |
| `Stop` | lezáró kör-jelzés nélküli megállás blokkolva (korlátosan) | fail-open |

A `Stop` szándékosan fail-open ÉS korlátos (alap: 2 blokkolás): egy hibás őr,
ami nem engedi befejezni a session-t, rosszabb a hiányzó őrnél — a láncnak van
elakadás-őre és self-healje, a végtelen ciklusból viszont nincs kiút.

Hook-szerződés: exit 0 = engedélyez, exit 2 = blokkol, a stderr a modellhez megy.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import tomllib
from pathlib import Path, PurePosixPath

BLOCK = 2
ALLOW = 0

# A kör saját jelző- és állapotfájljai: a burkoló és a `tools/codex-signal.sh`
# írja őket, ezért sosem scope-sértés.
ALWAYS_ALLOWED = (
    ".codex-round-status",
    ".mm-round-pid",
    ".wait-for-round-baseline",
    ".wait-for-router-baseline",
)

AI_ROUTER_BLOCK = re.compile(r"^```ai-router[ \t]*\n(.*?)^```[ \t]*$", re.MULTILINE | re.DOTALL)

# MÉRT tiltott parancsalakok: minta, megnevezés, alternatíva.
FORBIDDEN_BASH = (
    (
        re.compile(r"round-gate\.sh[^\n]*\|\s*(tail|head|grep|sed|awk)\b"),
        "a gate kimenetét csonkító pipe (`| tail`/`| head`/`| grep`)",
        "futtasd csonkítatlanul: tools/round-gate.sh <útvonalak>",
    ),
    (
        re.compile(r"round-gate\.sh[^\n]*&\s*$"),
        "a gate háttérbe küldése (`&`)",
        "a gate az egyetlen bizonyítékod — előtérben futtasd, és várd meg",
    ),
    (
        re.compile(r"flutter\s+analyze[^\n]*&&[^\n]*flutter\s+test"),
        "`analyze && test` lánc (ezen a boxon OOM-ot ad — docs/LESSONS.md L05)",
        "külön parancsként futtasd őket, vagy használd a tools/round-gate.sh-t",
    ),
    (
        re.compile(r"\bgit\s+stash\b"),
        "`git stash` a megosztott fán (mért adatvesztés-kockázat)",
        "commitolj a kör ágára — a stash másik session munkáját viheti el",
    ),
    (
        re.compile(r"\bgit\s+push\b[^\n]*(--force\b|--force-with-lease\b|\s-f\b)"),
        "force-push",
        "használd a tools/safe-force-push.sh artefaktumot",
    ),
    (
        re.compile(
            r"\b(pip3?\s+install|apt(-get)?\s+install|npm\s+(i|install)\b"
            r"|dart\s+pub\s+global\s+activate)\b"
        ),
        "csomagtelepítés a kör közben",
        "a kör a meglévő eszközökkel dolgozik; hiányzó eszköz → `stopped` jelzés",
    ),
    (
        re.compile(
            r"\bgit\s+-C\s+\S*music-theory\b[^\n]*\b"
            r"(checkout|switch|commit|reset|merge|rebase|stash|clean|push|cherry-pick)\b"
        ),
        "a MEGOSZTOTT fő munkafa módosítása",
        "a köröd a saját munkapéldányában dolgozik — a fő fához ne nyúlj",
    ),
)


def _emit(message: str) -> None:
    sys.stderr.write(message.rstrip() + "\n")


def _round_label() -> str:
    return os.environ.get("STRUMSIGHT_ROUND_ID", "a kör")


def _project_dir(payload: dict) -> Path:
    for candidate in (os.environ.get("CLAUDE_PROJECT_DIR"), payload.get("cwd"), os.getcwd()):
        if candidate:
            return Path(candidate).resolve()
    return Path.cwd().resolve()


def _allowed_paths(project: Path) -> tuple[str, ...]:
    """A kör `allowed_paths` listája a brief `ai-router` blokkjából.

    Elemzési hiba esetén kivételt dob — a hívó fail-closed módon blokkol.
    """
    raw = os.environ["STRUMSIGHT_ROUND_BRIEF"]
    brief = Path(raw)
    if not brief.is_absolute():
        brief = project / brief
    blocks = AI_ROUTER_BLOCK.findall(brief.read_text(encoding="utf-8"))
    if len(blocks) != 1:
        raise ValueError("a briefben nem pontosan egy ai-router blokk van")
    paths = tomllib.loads(blocks[0]).get("allowed_paths")
    if not isinstance(paths, list) or not paths:
        raise ValueError("az allowed_paths hiányzik vagy üres")
    return tuple(str(item) for item in paths)


def _relative(project: Path, raw: str) -> str:
    path = Path(raw)
    if not path.is_absolute():
        path = project / path
    try:
        return path.resolve().relative_to(project).as_posix()
    except ValueError:
        # A munkapéldányon KÍVÜLI útvonal nem a kör szerződése alá esik; a
        # megosztott fő fát a Bash-ág külön szabálya védi.
        return ""


def _is_allowed(relative: str, allowed: tuple[str, ...]) -> bool:
    if not relative or relative in ALWAYS_ALLOWED:
        return True
    candidate = PurePosixPath(relative)
    for entry in allowed:
        normalized = entry.rstrip("/")
        if relative == normalized:
            return True
        try:
            candidate.relative_to(PurePosixPath(normalized))
        except ValueError:
            continue
        return True
    return False


def _write_targets(payload: dict) -> list[str]:
    tool_input = payload.get("tool_input") or {}
    targets: list[str] = []
    for key in ("file_path", "notebook_path", "path"):
        value = tool_input.get(key)
        if isinstance(value, str) and value:
            targets.append(value)
    edits = tool_input.get("edits")
    if isinstance(edits, list):
        targets.extend(
            edit["file_path"]
            for edit in edits
            if isinstance(edit, dict) and isinstance(edit.get("file_path"), str)
        )
    return targets


def _guard_write(payload: dict) -> int:
    project = _project_dir(payload)
    try:
        allowed = _allowed_paths(project)
    except Exception as error:  # fail-closed: elemezhetetlen szerződés = nincs engedély
        _emit(
            f"IMPLEMENTER-ŐR: {_round_label()} briefjének allowed_paths listája nem "
            f"olvasható ({error}). Írás nem engedélyezett, amíg a szerződés "
            'elemezhetetlen — jelezz: tools/codex-signal.sh blocked "<egy sor>".'
        )
        return BLOCK

    for target in _write_targets(payload):
        relative = _relative(project, target)
        if _is_allowed(relative, allowed):
            continue
        _emit(
            f"IMPLEMENTER-ŐR: `{relative}` NINCS a(z) {_round_label()} engedélyezett "
            "fájllistáján (a brief ai-router blokkja).\n"
            "A lista tágítása TILOS (STOP-protokoll). Ha a munkához tényleg kell ez a "
            "fájl, állj meg és jelezd:\n"
            f'  tools/codex-signal.sh stopped "a kör {relative} fájlt igényel — brief-revízió kell"\n'
            f"Engedélyezett: {', '.join(allowed)}"
        )
        return BLOCK
    return ALLOW


def _guard_bash(payload: dict) -> int:
    command = (payload.get("tool_input") or {}).get("command")
    if not isinstance(command, str) or not command.strip():
        return ALLOW
    if "safe-force-push.sh" in command:
        return ALLOW
    for pattern, label, remedy in FORBIDDEN_BASH:
        if pattern.search(command):
            _emit(f"IMPLEMENTER-ŐR: tiltott parancsalak — {label}.\nHelyette: {remedy}.")
            return BLOCK
    return ALLOW


def _format_dart(payload: dict) -> int:
    targets = [target for target in _write_targets(payload) if target.endswith(".dart")]
    if not targets:
        return ALLOW
    dart = os.environ.get("DART_BIN") or str(Path.home() / "flutter" / "bin" / "dart")
    if not (Path(dart).is_file() and os.access(dart, os.X_OK)):
        return ALLOW
    project = _project_dir(payload)
    for target in targets:
        path = Path(target)
        if not path.is_absolute():
            path = project / path
        if not path.is_file():
            continue
        try:
            subprocess.run([dart, "format", str(path)], capture_output=True, timeout=90, check=False)
        except (OSError, subprocess.SubprocessError):
            return ALLOW  # a formázás kényelmi lépés, sosem buktathat kört
    return ALLOW


def _stop_state_file(project: Path) -> Path:
    digest = hashlib.sha256(str(project).encode()).hexdigest()[:16]
    return Path(tempfile.gettempdir()) / f"strumsight-stop-guard-{digest}"


def _guard_stop(payload: dict) -> int:
    project = _project_dir(payload)
    signal = project / ".codex-round-status"
    try:
        if signal.is_file():
            for line in signal.read_text(encoding="utf-8").splitlines():
                if re.fullmatch(r"status=(done|stopped|blocked)", line.strip()):
                    return ALLOW
    except OSError:
        return ALLOW  # fail-open: olvashatatlan jelzés nem wedge-elheti a session-t

    try:
        maximum = int(os.environ.get("STRUMSIGHT_STOP_GUARD_MAX", "2"))
    except ValueError:
        maximum = 2
    state = _stop_state_file(project)
    try:
        blocked_so_far = int(state.read_text(encoding="utf-8").strip() or "0")
    except (OSError, ValueError):
        blocked_so_far = 0
    if blocked_so_far >= maximum:
        _emit(
            "IMPLEMENTER-ŐR: a kör-jelzés továbbra is hiányzik, de az őr elérte a "
            f"{maximum} blokkolásos korlátját — a session lezárul, a lánc "
            "H-NOSIGNAL-lal fogja mérni."
        )
        return ALLOW
    try:
        state.write_text(str(blocked_so_far + 1), encoding="utf-8")
    except OSError:
        return ALLOW

    _emit(
        f"IMPLEMENTER-ŐR: a(z) {_round_label()} LEZÁRÓ KÖR-JELZÉS nélkül állna meg "
        f"({blocked_so_far + 1}/{maximum}).\n"
        "Jelzés nélkül a kör bukott: a lánc H-NOSIGNAL-t mér és önjavító kört indít "
        "(mérve 18 ilyen kör, egyikük 42 órás állással).\n"
        "Fejezd be a hátralévő munkát, majd add ki pontosan az egyiket:\n"
        '  tools/codex-signal.sh done "<egy soros összegzés>"\n'
        '  tools/codex-signal.sh stopped "<mi ütközik>"\n'
        '  tools/codex-signal.sh blocked "<mi hiányzik>"'
    )
    return BLOCK


def main() -> int:
    if not os.environ.get("STRUMSIGHT_ROUND_BRIEF"):
        return ALLOW  # nem implementer-kör: teljes no-op
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return ALLOW
    if not isinstance(payload, dict):
        return ALLOW

    event = payload.get("hook_event_name") or ""
    tool = payload.get("tool_name") or ""

    if event == "PreToolUse":
        if tool in ("Edit", "Write", "NotebookEdit", "MultiEdit"):
            return _guard_write(payload)
        if tool == "Bash":
            return _guard_bash(payload)
        return ALLOW
    if event == "PostToolUse":
        if tool in ("Edit", "Write", "MultiEdit"):
            return _format_dart(payload)
        return ALLOW
    if event == "Stop":
        return _guard_stop(payload)
    return ALLOW


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:  # pragma: no cover - védőháló
        _emit(f"IMPLEMENTER-ŐR: belső hiba ({error}) — a hívás átengedve.")
        sys.exit(ALLOW)
