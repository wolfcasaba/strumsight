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


class AlreadyMergedRoundTest(unittest.TestCase):
    """A MÉRT E13-R35 állapot: a kör MÁR merge-elve, mégis `REVIEW-APPROVED`.

    MÉRVE (E13-R35 H-NOSIGNAL, önjavítás 2026-08-27). Az orchestrátor-session
    16:30:09-kor indult, 4 órás abszolút időkorláttal. A PR #480 **20:28:30Z-kor
    zölden merge-elődött** (`57eeb6ff`; a `b4941257` head SHA-n `full-gate`,
    `router-ci` és `Coverage` mind `success`) — a driver 20:30:02-kor még be is
    ff-merge-elte a `main`-re. A session ezután 99 másodperccel a merge után,
    20:30:09-kor futott bele az abszolút időkorlátba, a záró rituálék (queue-sor
    `done`, HANDOFF, git-notes, **kör-jelzés**) előtt → H-NOSIGNAL.

    A halt maga ártalmatlan lenne: a kör kész. A kárt a KÖVETKEZŐ firing okozza.
    A queue-sor `pending` maradt, tehát a lánc újra sorra veszi a kört, és a
    `tools/round-resume-probe.sh` a javítás ELŐTT ezt mérte rá:

        ÁLLAPOT: REVIEW-APPROVED
        **TEENDŐ:** ... a kör a **merge-lépésnél** folytatódik: §0.3
        upstream-szinkron → PR → a teljes CI-kapu ... → zöld kapus squash-merge.

    Vagyis a szonda egy MÁR MERGE-ELT kört küld vissza a merge-lépésre: egy újabb
    4 órás session, egy duplikált PR egy olyan ágról, aminek a tartalma már a
    `main`-en van. A `--squash` merge miatt az ág csúcsa (`b4941257`) **nem** őse
    a `main`-nek (mérve: `git merge-base --is-ancestor` → 1), ezért a naiv
    ancestor-próba sem fogja meg; a `--delete-branch` sem futott le a timeout
    miatt, tehát a kör-ág is ott maradt az originon.

    A §0.2 örökség-létra legfelső foka (`REVIEW-APPROVED`) 2026-08-24 óta létezik,
    de a „már merge-elve" fok hiányzott róla.
    """

    # A VALÓDI kör adatai (nem kitalált fixture).
    MERGED_ROUND = "E13-R35"
    MERGED_BRANCH = "sonnet-impl/e13-r35-account-privacy-and-share"
    MERGED_REVIEW = "docs/reviews/e13-r35-review.md"
    # A `main` VALÓDI squash-merge commit-tárgya (`57eeb6ff`), szó szerint.
    MERGED_SUBJECT = (
        "[E13-R35] Account, Settings, Privacy, Offline AI és Share UI "
        "(UI-48, UI-62..UI-65) (#480)"
    )
    # Az ELŐZŐ kör merge-commitja a `main`-en — az idegen kör nem számít merge-nek.
    FOREIGN_SUBJECT = (
        "[E13-R34] Community challenges, clubs, notifications és safety UI "
        "(UI-59..UI-61)"
    )
    MERGED_APPROVED_REVIEW = """# E13-R35 review — Account, Privacy és Share UI

- **Végső döntés:** **APPROVED** (lásd §9)

**Nyitott lelet a merge után: 0.**

**VÉGSŐ DÖNTÉS: APPROVED.** Squash-merge mehet.
"""

    # Ugyanaz a csupasz-origin fixture és ugyanaz a szonda-hívás, mint fent —
    # explicit újrahasználat, hogy a fenti osztály tesztjei NE fussanak le mégegyszer.
    setUp = RoundResumeProbeTest.setUp
    _probe = RoundResumeProbeTest._probe

    def _publish_merged_round_branch(self):
        """A kör-ág publikálása az `origin`-ra, APPROVED review-val."""
        git(self.repo, "switch", "--quiet", "-c", self.MERGED_BRANCH, "main")
        review_file = self.repo / self.MERGED_REVIEW
        review_file.parent.mkdir(parents=True, exist_ok=True)
        review_file.write_text(self.MERGED_APPROVED_REVIEW)
        (self.repo / "lib").mkdir(parents=True, exist_ok=True)
        (self.repo / "lib" / "account_screen.dart").write_text("// account UI\n")
        git(self.repo, "add", "-A")
        git(self.repo, "commit", "--quiet", "-m", f"{self.MERGED_ROUND} implementáció + review")
        git(self.repo, "push", "--quiet", "origin", self.MERGED_BRANCH)
        head = subprocess.run(
            ["git", "-C", str(self.repo), "rev-parse", "HEAD"],
            check=True, capture_output=True, text=True,
        ).stdout.strip()
        git(self.repo, "switch", "--quiet", "main")
        return head

    def _squash_merge_to_main(self, subject: str) -> str:
        """A `gh pr merge --squash` hatása: ÚJ commit a `main`-en, a kör tárgyával.

        Az ág csúcsa emiatt NEM lesz őse a `main`-nek — pontosan úgy, ahogy az
        éles `57eeb6ff` sem őse-utódja a `b4941257`-nek.
        """
        git(self.repo, "switch", "--quiet", "main")
        (self.repo / "lib").mkdir(parents=True, exist_ok=True)
        (self.repo / "lib" / "account_screen.dart").write_text("// account UI\n")
        git(self.repo, "add", "-A")
        git(self.repo, "commit", "--quiet", "-m", subject)
        git(self.repo, "push", "--quiet", "origin", "main")
        merge_sha = subprocess.run(
            ["git", "-C", str(self.repo), "rev-parse", "HEAD"],
            check=True, capture_output=True, text=True,
        ).stdout.strip()
        git(self.repo, "fetch", "--quiet", "origin")
        return merge_sha

    def test_squash_merged_round_is_not_sent_back_to_the_merge_step(self) -> None:
        head = self._publish_merged_round_branch()
        merge_sha = self._squash_merge_to_main(self.MERGED_SUBJECT)

        # A mért éles előfeltétel: a squash miatt az ág csúcsa NEM őse a main-nek.
        ancestor = subprocess.run(
            ["git", "-C", str(self.repo), "merge-base", "--is-ancestor",
             head, "origin/main"],
            capture_output=True, text=True, check=False,
        )
        self.assertNotEqual(
            0, ancestor.returncode,
            "a fixture nem reprodukálja a squash-merge-öt (az ág csúcsa őse a main-nek)",
        )

        report = self._probe(round_id=self.MERGED_ROUND)

        self.assertIn("ÁLLAPOT: MERGE-ELVE", report, report)
        self.assertNotIn("ÁLLAPOT: REVIEW-APPROVED", report, report)
        self.assertIn(merge_sha[:12], report, report)
        # A besorolás nem elég: a jelentésnek meg kell TILTANIA az újra-merge-öt,
        # mert pontosan ide küldte volna vissza a `REVIEW-APPROVED` fok.
        self.assertRegex(
            report, r"(?i)nem\b.*(merge|PR)",
            f"a jelentés nem tiltja meg az újra-merge-öt / új PR-t:\n{report}",
        )
        # ...és ki kell mondania, mi maradt hátra: a LEZÁRÁS.
        self.assertRegex(
            report, r"(?i)queue|sor",
            f"a jelentés nem irányít a queue-sor lezárására:\n{report}",
        )

    def test_fast_forward_merged_round_is_also_detected(self) -> None:
        """Ha az ág csúcsa őse a `main`-nek (nem squash), az is merge-elt kör."""
        head = self._publish_merged_round_branch()
        git(self.repo, "switch", "--quiet", "main")
        git(self.repo, "merge", "--quiet", "--ff-only", self.MERGED_BRANCH)
        git(self.repo, "push", "--quiet", "origin", "main")
        git(self.repo, "fetch", "--quiet", "origin")

        report = self._probe(round_id=self.MERGED_ROUND)

        self.assertIn("ÁLLAPOT: MERGE-ELVE", report, report)
        self.assertIn(head[:12], report, report)

    def test_unmerged_approved_round_still_reads_as_merge_ready(self) -> None:
        """A fok nem eszi meg a `REVIEW-APPROVED`-ot: idegen kör merge-e nem számít."""
        self._publish_merged_round_branch()
        self._squash_merge_to_main(self.FOREIGN_SUBJECT)

        report = self._probe(round_id=self.MERGED_ROUND)

        self.assertIn("ÁLLAPOT: REVIEW-APPROVED", report, report)
        self.assertNotIn("ÁLLAPOT: MERGE-ELVE", report, report)


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

    def test_prompt_template_names_the_already_merged_rung(self) -> None:
        """A hiányzó fok: a kör MÁR merge-elve → lezárás, nem újabb merge-kísérlet."""
        template = PROMPT_TEMPLATE.read_text()
        self.assertIn(
            "MERGE-ELVE", template,
            "a §0.2 létrán nincs fok a MÁR MERGE-ELT körre — az E13-R35 (PR #480, "
            "`57eeb6ff`) így egy újabb 4 órás sessiont és egy duplikált PR-t kapott volna",
        )


if __name__ == "__main__":
    unittest.main()
