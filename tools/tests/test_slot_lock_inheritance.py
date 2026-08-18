"""A slot-zár nem szivároghat a tmux szerverbe (mérve 2026-08-18).

MÉRT hiba: a `tmux new-session` kliens FD-jeit a tmux SZERVER örökli, és a
szerver túléli a kört — amíg bármelyik session él. Az E07-R22 drivere által
18:13-kor indított szerver a 19:47-es merge után is fogta a `.pipeline/lock`-ot,
ezért `PIPELINE_SLOTS=2` mellett az 1-es slot tartósan foglalt maradt, és a lánc
NÉMÁN egysávosra esett vissza.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
PIPELINE = REPO_ROOT / "tools" / "round-pipeline.sh"

LOCK_PROBE = r"""
exec 9>"$1"
flock -n 9 || exit 3
%s
exit 0
"""

BUGGY = 'tmux -L "$2" new-session -d -s probe bash'
FIXED = '( exec 9>&-; tmux -L "$2" new-session -d -s probe bash )'


def lock_is_free(lock: Path) -> bool:
    """Egy MÁSIK processz meg tudja-e szerezni a zárat."""
    result = subprocess.run(
        ["flock", "-n", str(lock), "true"], capture_output=True, timeout=30
    )
    return result.returncode == 0


class SlotLockInheritanceTest(unittest.TestCase):
    def test_the_pipeline_closes_the_slot_lock_before_spawning_tmux(self) -> None:
        source = PIPELINE.read_text(encoding="utf-8")
        spawn = source.split("tmux new-session -d -s")[0]
        tail = spawn.rsplit("(", 1)[-1]
        self.assertIn(
            "exec 9>&-",
            tail,
            "a tmux-indítás nincs fd 9-et lezáró alhéjban — a szerver örökölné a slot-zárat",
        )

    @unittest.skipUnless(shutil.which("tmux"), "nincs tmux ezen a futón")
    @unittest.skipUnless(shutil.which("flock"), "nincs flock ezen a futón")
    def test_the_measured_leak_and_its_fix(self) -> None:
        """Falszifikáció: a javítás NÉLKÜLI alak tényleg fogva tartja a zárat."""
        for label, spawn, expected_free in (("javítás nélkül", BUGGY, False), ("javítással", FIXED, True)):
            with self.subTest(variant=label):
                with tempfile.TemporaryDirectory() as raw:
                    tmp = Path(raw)
                    lock = tmp / "slot.lock"
                    lock.touch()
                    socket = f"probe-{abs(hash(label)) % 100000}"
                    script = tmp / "probe.sh"
                    script.write_text(LOCK_PROBE % spawn, encoding="utf-8")
                    try:
                        subprocess.run(
                            ["bash", str(script), str(lock), socket],
                            capture_output=True,
                            timeout=60,
                            check=True,
                            env={**os.environ, "TMUX": ""},
                        )
                        self.assertEqual(
                            lock_is_free(lock),
                            expected_free,
                            f"{label}: a zár állapota nem a várt "
                            f"({'szabad' if expected_free else 'fogva tartott'})",
                        )
                    finally:
                        subprocess.run(["tmux", "-L", socket, "kill-server"],
                                       capture_output=True, timeout=30)


if __name__ == "__main__":
    unittest.main()
