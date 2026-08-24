"""Egy megölt orchestrátor-session után a lánc NE dobja el a kész kört.

MÉRT eset (E09-R26 H-NOSIGNAL, önjavítás 2026-08-24). Az E09-R26
orchestrátor-sessionje 17:48-kor `API Error: Server error mid-response`-ba
futott, és üres prompton némult el. A driver (15:15:07-kor indult, tehát még a
16:44:41-kor merge-elt elakadás-ébresztő ELŐTTI kódot futtatta) 18:08:49-kor
megölte, és H-NOSIGNAL-t jelzett.

A kör ekkor MÁR KÉSZ VOLT. Mérve a `minimax/e09-r26-user-report-and-immediate-
safety-flow` ág `520be629` csúcsán:

  * 22 kör-commit, 15 fájl, 4210 beszúrt sor (backend model + migration +
    router + service + tesztek, Flutter sheet + widget-tesztek, ARB-kulcsok);
  * `docs/reviews/e09-r26-review.md` → „**VÉGSŐ DÖNTÉS: APPROVED.**
    Squash-merge mehet." és „**Nyitott lelet a merge után: 0.**";
  * Full Gate (no APK) `32758663469` → `conclusion=success` PONTOSAN ezen a
    head SHA-n;
  * PR: EGY SEM — a session a `gh pr create` előtt halt meg.

A queue-sor `pending` maradt, tehát a lánc újra sorra veszi a kört. A
`docs/execution/pipeline-orchestrator-prompt.md` §0.2 örökség-létrája viszont
csak KÉT esetet nevez meg — „kész review **nyitott leletekkel**" (→ javító kör)
és „commitolt pre-flight" (→ ADR/brief újrahasznosítás) —, a kifutása pedig
„Ha csak félkész, jelöletlen munka van: hagyd, és **indíts tisztán**". Az
E09-R26 állapota (review APPROVED, NULLA nyitott lelet, zöld gate, nincs PR)
egyik nevesített fokra sem illik: a legspecifikusabb fok kifejezetten a nyitott
leletekhez van kötve. Egy újrainduló session tehát a kifutásra eshet, és
tisztán újrakezdhet egy már jóváhagyott, zölden mért kört — 4210 sor és egy
teljes review-ciklus veszne el, ADR 0422 divergens újraírásának kockázatával.

Ez a teszt azt a mérést rögzíti, ami ezt eldönti: a hagyaték-állapot nem a
session belátására van bízva, hanem MÉRVE megy be a promptba.
"""

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PROBE = ROOT / "tools" / "round-resume-probe.sh"
PROMPT_TEMPLATE = ROOT / "docs" / "execution" / "pipeline-orchestrator-prompt.md"
PIPELINE = ROOT / "tools" / "round-pipeline.sh"

# A VALÓDI ág- és fájlnevek a megállt körből (nem kitalált fixture).
REAL_ROUND = "E09-R26"
REAL_BRANCH = "minimax/e09-r26-user-report-and-immediate-safety-flow"
REAL_REVIEW = "docs/reviews/e09-r26-review.md"

# A VALÓDI review verdikt-sorai a `520be629` csúcsról, szó szerint.
REAL_APPROVED_REVIEW = """# E09-R26 review — Felhasználói report és azonnali safety flow

- **Végső döntés:** **APPROVED** (lásd §9)

## 8. Összegzés

**Nyitott BLOCKER/MAJOR: 0.** F1–F3 MINOR, F4–F5 NOTE — egyik sem
blokkoló.

## 9. Javító kör után — végső döntés

**Nyitott lelet a merge után: 0.** Minden BLOCKER/MAJOR/MINOR zárva.

**VÉGSŐ DÖNTÉS: APPROVED.** Squash-merge mehet.
"""

# Ugyanennek a körnek az ELSŐ fordulós, nyitott leletes állapota — ez a §0.2
# eddig is nevesített foka, és változatlanul javító kört kell adnia.
OPEN_FINDINGS_REVIEW = """# E09-R26 review — Felhasználói report és azonnali safety flow

- **Verdikt:** **CHANGES REQUIRED**

## 8. Összegzés

**Nyitott MAJOR: 2.** F1 UUID-validáció hiánya, F2 néma csonkítás.

**Verdikt: CHANGES REQUIRED** — a javító kör kötelező.
"""

# MÉRT szövegváltozat a repó review-korpuszából (`docs/reviews/*.md`): a javító
# kör után áthúzva marad a régi verdikt, és a SOR VÉGÉN áll az érvényes. A
# naiv „tartalmaz-e CHANGES REQUIRED" mérés ezt tévesen nyitottnak olvasná.
STRIKETHROUGH_REVIEW = """# E07-R11 review

**Verdikt: ~~CHANGES REQUIRED~~ → APPROVED** — a javító kör lezárta.
"""


def git(cwd, *args):
    subprocess.run(
        ["git", "-C", str(cwd), *args],
        check=True,
        capture_output=True,
        text=True,
    )


class RoundResumeProbeTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        # Az "origin" szerepét egy csupasz repó játssza — a szonda pontosan úgy
        # a remote-tracking refeket méri, ahogy az éles driver a fetch után.
        self.origin = self.tmp / "origin.git"
        git(self.tmp, "init", "--quiet", "--bare", "--initial-branch=main", str(self.origin))
        self.repo = self.tmp / "repo"
        git(self.tmp, "clone", "--quiet", str(self.origin), str(self.repo))
        git(self.repo, "config", "user.email", "heal@example.invalid")
        git(self.repo, "config", "user.name", "heal")
        (self.repo / "README.md").write_text("main\n")
        git(self.repo, "add", "README.md")
        git(self.repo, "commit", "--quiet", "-m", "main")
        git(self.repo, "push", "--quiet", "origin", "main")
        self.workspaces = self.tmp / "ws"
        self.workspaces.mkdir()

    def _publish_round_branch(self, *, review: str | None, branch: str = REAL_BRANCH):
        """Kör-ág publikálása az `origin`-ra: pre-flight commit + opcionális review."""
        git(self.repo, "switch", "--quiet", "-c", branch, "main")
        adr = self.repo / "docs" / "adr"
        adr.mkdir(parents=True, exist_ok=True)
        (adr / "0422-user-report-and-immediate-safety-flow.md").write_text("# ADR 0422\n")
        git(self.repo, "add", "-A")
        git(self.repo, "commit", "--quiet", "-m", f"{REAL_ROUND} pre-flight — ADR 0422")
        if review is not None:
            review_file = self.repo / REAL_REVIEW
            review_file.parent.mkdir(parents=True, exist_ok=True)
            review_file.write_text(review)
            git(self.repo, "add", "-A")
            git(self.repo, "commit", "--quiet", "-m", f"docs(review): {REAL_ROUND}")
        git(self.repo, "push", "--quiet", "origin", branch)
        head = subprocess.run(
            ["git", "-C", str(self.repo), "rev-parse", "HEAD"],
            check=True, capture_output=True, text=True,
        ).stdout.strip()
        git(self.repo, "switch", "--quiet", "main")
        git(self.repo, "fetch", "--quiet", "origin")
        return head

    def _probe(self, round_id: str = REAL_ROUND):
        completed = subprocess.run(
            [
                "bash", str(PROBE),
                "--round", round_id,
                "--repo", str(self.repo),
                "--no-fetch",
                "--workspace-glob", f"{self.workspaces}/ss-*",
            ],
            capture_output=True,
            text=True,
            check=False,
            env={**os.environ, "LC_ALL": "C.UTF-8"},
        )
        self.assertEqual(
            0, completed.returncode,
            f"a szonda nem futott le: stdout={completed.stdout!r} stderr={completed.stderr!r}",
        )
        return completed.stdout

    def test_approved_round_with_no_open_findings_is_merge_ready(self) -> None:
        """A MÉRT E09-R26 állapot: APPROVED review, 0 nyitott lelet, nincs PR."""
        head = self._publish_round_branch(review=REAL_APPROVED_REVIEW)
        report = self._probe()

        self.assertIn("ÁLLAPOT: REVIEW-APPROVED", report, report)
        self.assertIn(REAL_BRANCH, report, report)
        self.assertIn(head[:12], report, report)
        # A besorolás nem elég: a jelentésnek KI kell mondania a teendőt, mert
        # pontosan ez hiányzott a §0.2 létrájáról.
        self.assertRegex(
            report, r"(?i)nem.*(kezd|implement)",
            f"a jelentés nem tiltja meg az újrakezdést/újraimplementálást:\n{report}",
        )
        self.assertRegex(
            report, r"(?i)merge",
            f"a jelentés nem a merge-lépésre irányít:\n{report}",
        )

    def test_open_findings_still_mean_a_fix_round(self) -> None:
        """A §0.2 eddigi foka nem gyengülhet: nyitott lelet → javító kör."""
        self._publish_round_branch(review=OPEN_FINDINGS_REVIEW)
        report = self._probe()

        self.assertIn("ÁLLAPOT: REVIEW-NYITOTT", report, report)
        self.assertNotIn("ÁLLAPOT: REVIEW-APPROVED", report, report)

    def test_strikethrough_verdict_upgrade_reads_as_approved(self) -> None:
        """`~~CHANGES REQUIRED~~ → APPROVED`: a SOR VÉGI verdikt az érvényes."""
        self._publish_round_branch(review=STRIKETHROUGH_REVIEW)
        report = self._probe()

        self.assertIn("ÁLLAPOT: REVIEW-APPROVED", report, report)

    def test_preflight_only_branch_is_not_merge_ready(self) -> None:
        """Review nélküli kör-ág: az ADR/brief újrahasznosul, de nem merge-kész."""
        self._publish_round_branch(review=None)
        report = self._probe()

        self.assertIn("ÁLLAPOT: PRE-FLIGHT", report, report)
        self.assertNotIn("ÁLLAPOT: REVIEW-APPROVED", report, report)

    def test_no_leftover_means_a_clean_start(self) -> None:
        """Hagyaték nélkül a szonda nem talál ki munkát."""
        report = self._probe()

        self.assertIn("ÁLLAPOT: NINCS", report, report)

    def test_leftover_workspace_is_reported_even_without_a_branch(self) -> None:
        """A `ss-<motor>-eXX-rYY` munkapéldány mérve megy be (E06-R23 tanulság)."""
        leftover = self.workspaces / "ss-minimax-e09-r26"
        leftover.mkdir()
        report = self._probe()

        self.assertIn(str(leftover), report, report)

    def test_round_id_of_another_round_does_not_match(self) -> None:
        """A szonda nem húz be idegen kör ágát (`e09-r2` nem prefixel `e09-r26`-ot)."""
        self._publish_round_branch(review=REAL_APPROVED_REVIEW)
        report = self._probe(round_id="E09-R2")

        self.assertIn("ÁLLAPOT: NINCS", report, report)


class ResumeStateIsWiredIntoThePromptTest(unittest.TestCase):
    """A mérés csak akkor ér valamit, ha a session KÉZHEZ IS KAPJA."""

    def test_pipeline_substitutes_the_resume_state_placeholder(self) -> None:
        pipeline = PIPELINE.read_text()
        self.assertIn(
            "{{RESUME_STATE}}", pipeline,
            "a driver nem helyettesíti be a hagyaték-jelentést a prompt-sablonba",
        )
        self.assertIn("round-resume-probe.sh", pipeline, pipeline[:0])

    def test_prompt_template_consumes_the_measured_report(self) -> None:
        template = PROMPT_TEMPLATE.read_text()
        self.assertIn(
            "{{RESUME_STATE}}", template,
            "a §0.2 örökség-létra nem olvassa a mért hagyaték-jelentést",
        )

    def test_prompt_template_names_the_approved_rung(self) -> None:
        """A hiányzó fok: APPROVED review + zöld gate → merge-lépés, nem újrakezdés."""
        template = PROMPT_TEMPLATE.read_text()
        self.assertIn(
            "REVIEW-APPROVED", template,
            "a §0.2 létrán nincs fok az APPROVED, nyitott lelet nélküli körre — "
            "pontosan ez ejtette volna el az E09-R26 4210 sorát",
        )


if __name__ == "__main__":
    unittest.main()
