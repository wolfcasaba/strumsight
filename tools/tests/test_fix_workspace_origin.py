"""Regressziós teszt: tools/fix-workspace-origin.sh (self-heal E06-R07/H7).

MÉRT gyökérok (2026-08-11, docs/LESSONS.md L220): a kör-munkapéldányt az
orchesztrátor `git clone <hub> <cél>`-lal hozza létre (sdd-round-driver
SKILL.md §3), ahol `<hub>` a checkoutolt fő-repó lokális útvonala. Ha a hub
ÉPP a kör branch-én áll (pl. a pre-flight ADR/brief-commit után, a `main`-re
visszaváltás előtt), az implementer klón `origin`-je a hub lokális útvonalára
mutat, és egy push onnan `receive.denyCurrentBranch`-sel elutasul: a cél
nem-bare repo, a frissítendő ref pedig egyezik a checkoutolt branch-csel.
Ez pontosan a `2e55359c` commit sorsa volt E06-R07 második implementer-
kísérletében — elkészült, de reviewzhatatlan/merge-elhetetlen maradt.

Hermetikus: három egymásba ágyazott tempdir-repóval reprodukálja a mért
alakot (bare "upstream" = GitHub helyettese, nem-bare "hub" = a checkoutolt
fő-repó helyettese, "workdir" = az implementer klón helyettese) — nem a
valódi /home/ubuntu/music-theory-t vagy annak remote-jait használja.
"""

import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools" / "fix-workspace-origin.sh"
BRANCH = "codex/e06-r07-signal-quality-stage"


def _git(*args, cwd):
    return subprocess.run(
        ["git", *args],
        cwd=cwd,
        text=True,
        capture_output=True,
        check=True,
    )


def _init_repo(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)
    _git("init", "-q", cwd=path)
    _git("config", "user.email", "heal@example.invalid", cwd=path)
    _git("config", "user.name", "Heal Test", cwd=path)


class FixWorkspaceOriginTest(unittest.TestCase):
    def test_rewrites_local_hub_origin_and_unblocks_the_measured_push_failure(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as directory_name:
            root = Path(directory_name)
            upstream = root / "upstream.git"
            hub = root / "hub"
            workdir = root / "workdir"

            subprocess.run(
                ["git", "init", "-q", "--bare", str(upstream)], check=True
            )
            # `file://`, nem a bare nyers útvonala: a hub SAJÁT upstream-je a
            # mért éles alakot (valódi URL-séma) tükrözi, nem egy másik lokális
            # útvonalat — a script pontosan ezt a különbséget vizsgálja.
            _git("clone", "-q", f"file://{upstream}", str(hub), cwd=root)
            _git("config", "user.email", "heal@example.invalid", cwd=hub)
            _git("config", "user.name", "Heal Test", cwd=hub)
            (hub / "README.md").write_text("seed\n", encoding="utf-8")
            _git("add", "README.md", cwd=hub)
            _git("commit", "-q", "-m", "seed", cwd=hub)
            _git("push", "-q", "origin", "HEAD:refs/heads/main", cwd=hub)

            # A hub a kör pre-flight brief/ADR-commitja után a kör branch-én
            # marad — a mért leftover állapot az implementer-klónozás
            # pillanatában.
            _git("switch", "-q", "-c", BRANCH, cwd=hub)
            (hub / "docs.md").write_text("brief\n", encoding="utf-8")
            _git("add", "docs.md", cwd=hub)
            _git("commit", "-q", "-m", "docs(e06-r07): prepare", cwd=hub)
            _git("push", "-q", "-u", "origin", BRANCH, cwd=hub)

            _git("clone", "-q", "--branch", BRANCH, str(hub), str(workdir), cwd=root)
            # A klón SAJÁT, friss .git/config-ot kap — a hub identitása nem
            # öröklődik, és a CI-futón (ellentétben a dev boxszal) nincs
            # globális git user.name/email, ezért ezt explicit be kell állítani.
            _git("config", "user.email", "heal@example.invalid", cwd=workdir)
            _git("config", "user.name", "Heal Test", cwd=workdir)
            (workdir / "impl.txt").write_text("feat\n", encoding="utf-8")
            _git("add", "impl.txt", cwd=workdir)
            _git("commit", "-q", "-m", "feat: implementer commit", cwd=workdir)

            self.assertEqual(
                _git("remote", "get-url", "origin", cwd=workdir).stdout.strip(),
                str(hub),
                "a klón origin-je induláskor a hub LOKÁLIS útvonala",
            )

            # RED — a mért hiba: a hub a saját checkoutolt branch-ére nem
            # fogadja el a push-t.
            red = subprocess.run(
                ["git", "push", "origin", BRANCH],
                cwd=workdir,
                text=True,
                capture_output=True,
            )
            self.assertNotEqual(red.returncode, 0, red.stdout + red.stderr)
            self.assertIn("denyCurrentBranch", red.stderr)

            fixed = subprocess.run(
                [str(SCRIPT), str(workdir)],
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(fixed.returncode, 0, fixed.stdout + fixed.stderr)

            self.assertEqual(
                _git("remote", "get-url", "origin", cwd=workdir).stdout.strip(),
                f"file://{upstream}",
                "a javítás után az origin a hub SAJÁT upstream-je, nem a hub "
                "lokális útvonala",
            )

            # GREEN — a push most egyenesen a (bare) upstream-re megy, ahol a
            # denyCurrentBranch fogalma nem is értelmezhető.
            green = subprocess.run(
                ["git", "push", "origin", BRANCH],
                cwd=workdir,
                text=True,
                capture_output=True,
            )
            self.assertEqual(green.returncode, 0, green.stdout + green.stderr)

    def test_leaves_an_already_url_origin_untouched(self) -> None:
        with tempfile.TemporaryDirectory() as directory_name:
            workdir = Path(directory_name) / "workdir"
            _init_repo(workdir)
            (workdir / "f.txt").write_text("x\n", encoding="utf-8")
            _git("add", "f.txt", cwd=workdir)
            _git("commit", "-q", "-m", "seed", cwd=workdir)
            _git(
                "remote",
                "add",
                "origin",
                "https://github.com/wolfcasaba/strumsight.git",
                cwd=workdir,
            )

            result = subprocess.run(
                [str(SCRIPT), str(workdir)],
                text=True,
                capture_output=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(
                _git("remote", "get-url", "origin", cwd=workdir).stdout.strip(),
                "https://github.com/wolfcasaba/strumsight.git",
            )

    def test_missing_origin_is_a_harmless_no_op(self) -> None:
        with tempfile.TemporaryDirectory() as directory_name:
            workdir = Path(directory_name) / "workdir"
            _init_repo(workdir)
            (workdir / "f.txt").write_text("x\n", encoding="utf-8")
            _git("add", "f.txt", cwd=workdir)
            _git("commit", "-q", "-m", "seed", cwd=workdir)

            result = subprocess.run(
                [str(SCRIPT), str(workdir)],
                text=True,
                capture_output=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_hub_whose_own_upstream_is_also_a_local_path_is_left_untouched(
        self,
    ) -> None:
        # Ha a hub SAJÁT origin-je sem valódi URL (pl. egy másik lokális
        # tesztfixture), a script nem talál ki upstream-et — biztonságos
        # alapállás: nem nyúl az eredeti origin-hez.
        with tempfile.TemporaryDirectory() as directory_name:
            root = Path(directory_name)
            hub = root / "hub"
            other_local = root / "some-other-local-repo"
            workdir = root / "workdir"

            _init_repo(hub)
            (hub / "f.txt").write_text("x\n", encoding="utf-8")
            _git("add", "f.txt", cwd=hub)
            _git("commit", "-q", "-m", "seed", cwd=hub)
            _init_repo(other_local)
            (other_local / "f.txt").write_text("x\n", encoding="utf-8")
            _git("add", "f.txt", cwd=other_local)
            _git("commit", "-q", "-m", "seed", cwd=other_local)
            _git("remote", "add", "origin", str(other_local), cwd=hub)

            _git("clone", "-q", str(hub), str(workdir), cwd=root)

            result = subprocess.run(
                [str(SCRIPT), str(workdir)],
                text=True,
                capture_output=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(
                _git("remote", "get-url", "origin", cwd=workdir).stdout.strip(),
                str(hub),
            )


if __name__ == "__main__":
    unittest.main()
