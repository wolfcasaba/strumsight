"""Biztonságos rebase-utáni push (ADR 0242 §5.5, D3).

MÉRT ok (2026-08-13, E06-R23 H8, majdnem adatvesztés). Egy konfliktus nélküli
rebase után a `git push --force-with-lease` (argumentum nélkül) elutasításra
futott, mert a remote közben előrement egy másik commit-tal (a security
review push-a). A halt téves diagnózisa ("branch-szabály") és a javasolt
"fetch, majd force-with-lease" feloldás szó szerint végrehajtva ELDOBTA volna
azt a commitot.

`tools/safe-force-push.sh` ezt teszi futtatható protokollá: PONTOS fetch →
remote-only commitok PATCH-ID alapú felsorolása → megtagadás lista nélkül
push NÉLKÜL, vagy MÉRT SHA-ra vett explicit lease-es push.

Ezek a tesztek lokális bare repókat használnak "origin" gyanánt — nincs
hálózat, nincs valódi GitHub-hívás.
"""

import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools" / "safe-force-push.sh"


def git(repo: Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["git", "-C", str(repo), *args],
        check=True,
        capture_output=True,
        text=True,
    )


def rev_parse(repo: Path, ref: str) -> str:
    return git(repo, "rev-parse", ref).stdout.strip()


def init_clone(bare: Path, dest: Path, who: str) -> None:
    subprocess.run(["git", "clone", "-q", str(bare), str(dest)], check=True, capture_output=True)
    git(dest, "config", "user.email", f"{who}@x.test")
    git(dest, "config", "user.name", who)


def write_commit(repo: Path, filename: str, content: str, message: str) -> None:
    (repo / filename).write_text(content, encoding="utf-8")
    git(repo, "add", filename)
    git(repo, "commit", "-q", "-m", message)


def run_safe_force_push(repo: Path, branch: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["bash", str(SCRIPT), branch],
        cwd=str(repo),
        capture_output=True,
        text=True,
        timeout=60,
    )


def base_scenario(root: Path):
    """origin(bare) <- work(base commit, branch 'feature' pushed).

    A visszaadott (bare, work) párral a hívó felépítheti a saját ütközés-
    vagy tiszta-eset forgatókönyvét.
    """
    bare = root / "origin.git"
    subprocess.run(["git", "init", "-q", "--bare", "-b", "main", str(bare)], check=True)

    work = root / "work"
    init_clone(bare, work, "work")
    # a bare repónak még nincs commitja -- a klón üres; hozzunk létre egy
    # kezdő ágat és pusholjuk fel, majd checkoutoljuk 'feature'-ként.
    write_commit(work, "f.txt", "base\n", "base")
    git(work, "branch", "-M", "main")
    git(work, "push", "-q", "-u", "origin", "main")
    git(work, "checkout", "-q", "-b", "feature")
    git(work, "push", "-q", "-u", "origin", "feature")
    return bare, work


class RefusalTest(unittest.TestCase):
    """A7/A8: a script megtagadja a pusht, ha a remote-on veszélyben lévő
    (nem rebaseelt-ekvivalens) commit van, és FELSOROLJA azt."""

    def test_it_refuses_when_the_remote_has_commits_we_lack(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            bare, work = base_scenario(root)

            # "other" pusholja a feature-t egy ÚJ commit-tal, amit a work
            # sosem fetchel le.
            other = root / "other"
            init_clone(bare, other, "other")
            git(other, "checkout", "-q", "feature")
            write_commit(other, "f.txt", "base\nremote-only change\n", "remote-only commit")
            git(other, "push", "-q", "origin", "feature")
            remote_sha_before = rev_parse(other, "feature")

            # a work saját, FÜGGETLEN commitja (nem fetchelte a remote-only-t)
            write_commit(work, "g.txt", "local\n", "local-only commit")

            result = run_safe_force_push(work, "feature")

            self.assertEqual(result.returncode, 3, result.stderr)
            remote_sha_after = git(bare, "rev-parse", "feature").stdout.strip()
            self.assertEqual(
                remote_sha_after,
                remote_sha_before,
                "megtagadás után a remote ref-nek VÁLTOZATLANNAK kell maradnia -- push nem történt",
            )

    def test_the_refusal_names_the_remote_only_commits(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            bare, work = base_scenario(root)

            other = root / "other"
            init_clone(bare, other, "other")
            git(other, "checkout", "-q", "feature")
            write_commit(other, "f.txt", "base\nremote-only change\n", "remote-only commit")
            git(other, "push", "-q", "origin", "feature")
            remote_sha = rev_parse(other, "feature")

            write_commit(work, "g.txt", "local\n", "local-only commit")

            result = run_safe_force_push(work, "feature")

            self.assertEqual(result.returncode, 3, result.stderr)
            self.assertIn(remote_sha, result.stderr, result.stderr)
            self.assertIn("remote-only commit", result.stderr, result.stderr)


class SuccessfulPushTest(unittest.TestCase):
    """A9/A10: tiszta esetben (nincs remote-only) a push explicit, a
    FRISSEN mért remote SHA-ra vett lease-szel megy -- a lokális, esetleg
    ELAVULT tracking-ref sosem elég (ez okozta a mért H8-at)."""

    def _rebase_equivalent_scenario(self, root: Path):
        bare, work = base_scenario(root)

        # "other" pusholja ugyanazt a tartalmi változtatást, amit a work is
        # meg fog csinálni -- a lokális tracking-ref work-ban eközben
        # ELAVULT marad (a work sosem fetchel explicit módon).
        other = root / "other"
        init_clone(bare, other, "other")
        git(other, "checkout", "-q", "feature")
        write_commit(other, "f.txt", "base\nshared change\n", "shared change")
        git(other, "push", "-q", "origin", "feature")
        remote_sha = rev_parse(other, "feature")

        # a work UGYANAZT a tartalmi diffet hozza létre lokálisan, FÜGGETLEN
        # commit-ként (más SHA, azonos patch-id -- mint egy valódi rebase
        # eredménye).
        write_commit(work, "f.txt", "base\nshared change\n", "shared change")

        # ellenőrzés: a work lokális remote-tracking refje MÉG a régi (base),
        # mert sosem fetchelt -- a script SAJÁT fetch-lépésének kell
        # frissítenie, mielőtt a lease-t számolja.
        stale_tracking = rev_parse(work, "refs/remotes/origin/feature")
        self.assertNotEqual(
            stale_tracking, remote_sha, "előfeltétel: a work tracking-refje elavult legyen"
        )

        return bare, work, remote_sha

    def test_the_push_uses_an_explicit_lease_on_the_measured_remote_sha(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            bare, work, remote_sha_before = self._rebase_equivalent_scenario(root)

            result = run_safe_force_push(work, "feature")

            self.assertEqual(result.returncode, 0, result.stderr)
            # ha a script a RÉGI (elavult, sosem frissített) tracking-refet
            # használta volna lease-nek, a git ELUTASÍTOTTA volna a pusht,
            # mert a remote tényleges állapota (remote_sha_before) eltér
            # attól -- a SIKERES push tehát bizonyítja, hogy a lease a
            # FRISSEN mért SHA-ra ment.
            new_remote_sha = git(bare, "rev-parse", "feature").stdout.strip()
            self.assertEqual(new_remote_sha, rev_parse(work, "HEAD"))
            self.assertNotEqual(new_remote_sha, remote_sha_before)

    def test_rebased_equivalents_are_not_treated_as_remote_only(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            _bare, work, _remote_sha_before = self._rebase_equivalent_scenario(root)

            result = run_safe_force_push(work, "feature")

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn("MEGTAGADVA", result.stderr, result.stderr)


class UsageTest(unittest.TestCase):
    def test_missing_branch_argument_is_a_usage_error(self) -> None:
        result = subprocess.run(
            ["bash", str(SCRIPT)], capture_output=True, text=True, timeout=30
        )
        self.assertEqual(result.returncode, 2)


if __name__ == "__main__":
    unittest.main()
