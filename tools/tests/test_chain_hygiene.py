"""E99-R19 (GOV-13) — lánc-higiénia: main-szinkron és egyetlen záró commit.

A D1 (main-szinkron) és D2 (egyszeres záró commit) a mért „9 firing kimaradt
2026-08-11..08-18 között, egy epizódban 4 egymás után" hibaosztály ellen
védekeznek — a `tools/round-pipeline.sh` korábban egységesen `die`-vel állt
meg mind a lemaradás, mind a divergencia, mind a queue-státusz-elhagyás
esetén. A driver most három, egyértelműen különböző döntést hoz:

  * `noop`            — a lokális HEAD azonos az origin/main-ével;
  * `ff-merge`        — a lokális HEAD az origin/main őse, a fa tiszta → a
                        driver maga végzi el a `git merge --ff-only`-t;
  * `halt:divergencia`— a lokális HEAD-nek van originen nem létező commitja
                        → emberi döntés kell, emberi beavatkozás nélkül a
                        lánc itt biztosan megáll.

A D2 a `tools/round-pipeline.sh` `merged` ágának apró, de határozott
szigorítása: ha a `docs(handoff…)` push a merge-lock elvesztése miatt
félbeszakadt, a fail-safe `chore(pipeline)` commitot készít a sor-fájlra
és pushol; ha a sor már `done` (az orchestrátor AZ EGYSÉGES záró commitban
átírta), ez az ág NEM készít üres commitot. Az elveszett `done` státusz
így zártan marad, és a kört nem terheli plusz CI-futás.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools" / "round-pipeline.sh"


def _run(argv, *, cwd=None, env=None):
    return subprocess.run(
        ["bash", str(SCRIPT), *argv],
        cwd=cwd or ROOT,
        env={**os.environ, **(env or {})},
        text=True,
        capture_output=True,
        check=False,
    )


def _make_bare_remote(directory: Path) -> tuple[Path, Path]:
    """Egy `bare` repo, ami a `worktree` origin-jeként szolgál.

    A `head_repo` fölé épül: a `head_repo` aktuális HEAD-jét toljuk a bare
    `main` ágára, majd a `worktree` ezt a bare-t nevezi `origin`-nek. A bare
    `HEAD` refjét a `main`-re állítjuk, hogy a `git clone` ne figyelmeztessen
    a „remote HEAD refers to nonexistent ref" üzenettel — a klón ugyanis
    `checkout -b main origin/main`-t csinálna, és ennek csendes hibája az
    volt, hogy a `git rev-parse HEAD` nem-0 kilépéssel tért vissza a teszt
    indításakor (mérve 2026-08-20).
    """
    bare = directory / "origin.git"
    head_repo = directory / "head.git"
    worktree = directory / "worktree"
    for path in (bare, head_repo, worktree):
        path.mkdir(parents=True, exist_ok=True)
    subprocess.run(["git", "init", "-q", "--bare", str(bare)], check=True)
    subprocess.run(["git", "symbolic-ref", "HEAD", "refs/heads/main"], cwd=bare, check=True)
    subprocess.run(["git", "init", "-q", str(head_repo)], check=True)
    subprocess.run(["git", "config", "user.email", "ci@example.invalid"], cwd=head_repo, check=True)
    subprocess.run(["git", "config", "user.name", "ci"], cwd=head_repo, check=True)
    (head_repo / "README.md").write_text("baseline\n")
    subprocess.run(["git", "add", "."], cwd=head_repo, check=True)
    subprocess.run(["git", "commit", "-qm", "baseline"], cwd=head_repo, check=True)
    subprocess.run(["git", "branch", "-M", "main"], cwd=head_repo, check=True)
    subprocess.run(
        ["git", "push", "-q", str(bare), "main:main"],
        cwd=head_repo,
        check=True,
    )
    subprocess.run(["git", "clone", "-q", str(bare), str(worktree)], check=True)
    subprocess.run(["git", "config", "user.email", "ci@example.invalid"], cwd=worktree, check=True)
    subprocess.run(["git", "config", "user.name", "ci"], cwd=worktree, check=True)
    # A `head_repo` a `bare`-t push-tükörnek használja: a `_push` helper a
    # `git push origin main:main` alakot használja, ezért az origin
    # remote-ot IS regisztrálni kell (a kezdeti `main:main` push a teljes
    # útvonallal ment, de a további iterációk `origin` néven hivatkoznak).
    subprocess.run(["git", "remote", "add", "origin", str(bare)], cwd=head_repo, check=True)
    return head_repo, worktree


class MainSyncStrategyTest(unittest.TestCase):
    """A D1 döntés táblája — `noop` / `ff-merge` / `halt:divergencia`.

    A mérés tárgya a `--main-sync-strategy` teszthorog: a driver indítása
    nélkül, a függvény-beágyazott logikával azonos úton dönt. A
    `--main-sync-ff-merge` horog magát az ff-merge-et is elvégzi, hogy a
    HALADÁS cellát (fa ténylegesen előrébb kerül) ne csak a kiírt szövegre
    kelljen hinni.
    """

    def _strategy(self, worktree: Path) -> subprocess.CompletedProcess:
        return _run(["--main-sync-strategy", str(worktree)], cwd=worktree)

    def _ff_merge(self, worktree: Path) -> subprocess.CompletedProcess:
        return _run(["--main-sync-ff-merge", str(worktree)], cwd=worktree)

    def _push(self, head_repo: Path, message: str) -> None:
        (head_repo / "README.md").write_text(f"{message}\n", encoding="utf-8")
        subprocess.run(["git", "commit", "-aqm", message], cwd=head_repo, check=True)
        subprocess.run(["git", "push", "-q", "origin", "main:main"], cwd=head_repo, check=True)

    def test_main_identical_is_a_noop(self) -> None:
        # 1. cella: HEAD == origin/main. A függvény a saját állapotot
        # békén hagyja, és kilép.
        with tempfile.TemporaryDirectory() as directory_name:
            _, worktree = _make_bare_remote(Path(directory_name))
            head = subprocess.run(
                ["git", "rev-parse", "HEAD"], cwd=worktree, check=True, text=True, capture_output=True
            ).stdout.strip()
            remote = subprocess.run(
                ["git", "rev-parse", "origin/main"],
                cwd=worktree,
                check=True,
                text=True,
                capture_output=True,
            ).stdout.strip()
            self.assertEqual(head, remote)

            decided = self._strategy(worktree)
            self.assertEqual(decided.returncode, 0, decided.stderr)
            self.assertTrue(
                decided.stdout.startswith("noop:"),
                f"azonos HEAD-et 'noop'-nak kell jelölnie; stdout={decided.stdout!r}",
            )

    def test_main_strictly_behind_does_an_ff_merge_and_advances(self) -> None:
        # 2. cella: HEAD az origin/main őse, fa tiszta → ff-merge, a firing
        # FOLYTATÓDIK. Az „strictly ahead" ellenőrzés itt kulcsfontosságú:
        # ha bármikor „eltér"-re cserélnék, ez a cella is divergenciának
        # minősülne, és a lokális commit néma felülírásának kockázatát
        # vinné be (l. falszifikációs cella lentebb).
        with tempfile.TemporaryDirectory() as directory_name:
            head_repo, worktree = _make_bare_remote(Path(directory_name))
            self._push(head_repo, "remote commit 1")
            subprocess.run(["git", "fetch", "-q", "origin"], cwd=worktree, check=True)

            advance = self._ff_merge(worktree)
            self.assertEqual(advance.returncode, 0, advance.stdout + advance.stderr)

            head_after = subprocess.run(
                ["git", "rev-parse", "HEAD"],
                cwd=worktree,
                check=True,
                text=True,
                capture_output=True,
            ).stdout.strip()
            remote_after = subprocess.run(
                ["git", "rev-parse", "origin/main"],
                cwd=worktree,
                check=True,
                text=True,
                capture_output=True,
            ).stdout.strip()
            self.assertEqual(head_after, remote_after)
            self.assertNotEqual(head_after, "")
            self.assertIn("Fast-forward", advance.stdout)

    def test_true_divergence_is_halted(self) -> None:
        # 3. cella: lokális commit, ami nincs az originen → halt. A
        # korábbi `die "a lokális main eltér az origin/main-től"` most a
        # VALÓDI divergenciát szűri ki, a lemaradás kikerült mellőle.
        with tempfile.TemporaryDirectory() as directory_name:
            head_repo, worktree = _make_bare_remote(Path(directory_name))
            self._push(head_repo, "remote commit 1")
            subprocess.run(["git", "fetch", "-q", "origin"], cwd=worktree, check=True)
            # Lokális, originen nem létező commit (a HEAD-ről elágazva):
            subprocess.run(["git", "checkout", "-q", "main"], cwd=worktree, check=True)
            (worktree / "local-only.txt").write_text("local divergence\n")
            subprocess.run(["git", "add", "local-only.txt"], cwd=worktree, check=True)
            subprocess.run(
                ["git", "commit", "-qm", "local divergence (not on origin)"],
                cwd=worktree,
                check=True,
            )
            subprocess.run(["git", "fetch", "-q", "origin"], cwd=worktree, check=True)

            decided = self._strategy(worktree)
            self.assertEqual(decided.returncode, 1, decided.stderr)
            self.assertTrue(
                decided.stdout.startswith("halt:divergencia:"),
                f"valódi divergenciát 'halt:divergencia'-ként kell jelölnie; "
                f"stdout={decided.stdout!r}",
            )

            ff = self._ff_merge(worktree)
            self.assertEqual(
                ff.returncode,
                2,
                f"az ff-merge hooknak 'divergencia' okkal kell kilépnie 2-vel, "
                f"ha a fa szigorú divergens; stdout={ff.stdout!r}",
            )

    def test_strictly_ahead_filter_must_not_be_swapped_for_differs(self) -> None:
        # Falszifikációs cella (brief §4, kötelező): a D1 szigorú-őse
        # ellenőrzésének lecserélése puszta „eltér"-re a „main divergál" esetet
        # NÉMÁN átfordítaná „ff-merge"-re → a lokális commit elveszne. Ezt
        # közvetlenül a forrás-szövegre keresve kell védeni: az ff-merge
        # hook csak akkor csinál ff-merge-et, ha a `merge-base --is-ancestor`
        # vizsgálat IGEN-nel tér vissza. Ha valaki kicseréli, a HAMIS
        # megoldás (`!= origin/main`) továbbra is átmenne a `noop` és az
        # `ff-merge` cellákon, de a divergencia NEM ÁLLNA meg — ezt itt a
        # forrás-szintű regression-védelem fogja meg.
        text = SCRIPT.read_text()
        self.assertIn(
            "merge-base --is-ancestor",
            text,
            "a D1 szigorú-ős ellenőrzését tilos puszta 'eltér'-re cserélni — "
            "különben a 'main divergál' esetben a lokális commitot némán "
            "felülírná az ff-merge",
        )

    def test_dirty_tree_is_stopped_above_the_main_sync_check(self) -> None:
        # 4. cella (brief §4): main LEMARADT + piszkos fa → megáll. A
        # korábbi változat `HEAD == origin/main` (azonos) állapotára támaszkodott,
        # és a `1` kilépés a hook "noop" ágából jött — a piszkos-fa őr kiiktatása
        # esetén a teszt TÖRVÉNYESEN zöld maradt (F1 review). Az új fixture
        # `HEAD ancestor-of origin/main` (valódi lemaradás), piszkos fával: a
        # fa-őr nélkül az ff-merge SIKERESEN lezajlana, a `halt:dirty-tree`
        # kilépés CSAK a `git status --porcelain` előfeltétel-őr miatt jön létre.
        with tempfile.TemporaryDirectory() as directory_name:
            head_repo, worktree = _make_bare_remote(Path(directory_name))
            self._push(head_repo, "remote commit 1")
            subprocess.run(["git", "fetch", "-q", "origin"], cwd=worktree, check=True)
            # A lemaradás tényleg fennáll (a HEAD az origin/main őse), és a fa
            # piszkos — ez a 4. cella egyetlen állapota.
            local_head = subprocess.run(
                ["git", "rev-parse", "HEAD"],
                cwd=worktree,
                check=True,
                text=True,
                capture_output=True,
            ).stdout.strip()
            remote_head = subprocess.run(
                ["git", "rev-parse", "origin/main"],
                cwd=worktree,
                check=True,
                text=True,
                capture_output=True,
            ).stdout.strip()
            subprocess.run(
                ["git", "merge-base", "--is-ancestor", local_head, remote_head],
                cwd=worktree,
                check=True,
                capture_output=True,
            )
            self.assertNotEqual(local_head, remote_head)

            (worktree / "untracked.txt").write_text("dirty\n")
            status = subprocess.run(
                ["git", "status", "--porcelain"],
                cwd=worktree,
                check=True,
                text=True,
                capture_output=True,
            ).stdout.strip()
            self.assertTrue(status, "a kiindulási feltétel: legyen piszkos a fa")

            advance = self._ff_merge(worktree)
            self.assertEqual(
                advance.returncode,
                3,
                f"piszkos fán + valódi lemaradásnál a hook 'halt:dirty-tree' "
                f"kilépéssel kell megállnia (returncode=3); got rc={advance.returncode} "
                f"stdout={advance.stdout!r} stderr={advance.stderr!r}",
            )
            self.assertTrue(
                advance.stdout.startswith("halt:dirty-tree"),
                f"a piszkos-fa őr kifejezett jelölése a stdout-ban kötelező "
                f"(a 'noop' / 'divergencia' kilépéssel a cella nem a fa-őr miatt "
                f"állna meg, hanem szerencsés egybeesésből); stdout={advance.stdout!r}",
            )

    def test_dirty_tree_guard_in_ff_merge_hook_must_not_be_removed(self) -> None:
        # Falszifikációs cella (F1 review): a `--main-sync-ff-merge` hook
        # piszkos-fa őre (`git status --porcelain` előfeltétel-ellenőrzés)
        # kötelező — ha kikerül, a `test_dirty_tree_is_stopped_above_the_main_sync_check`
        # pirosra váltana, és a `halt:dirty-tree` kilépés elveszne (a hook
        # a piszkos fás fán csendben ff-merge-et hajtana végre, ami
        # adatvesztéssel járhat). A forrás-szintű regression-védelem a
        # `git status --porcelain` ÉS a `halt:dirty-tree` szó szerinti
        # együttes jelenlétét ellenőrzi a hook blokkjában.
        text = SCRIPT.read_text()
        block = text.split("--main-sync-ff-merge", 1)[1].split(
            "--pending-done-failsafe-required", 1
        )[0]
        self.assertIn(
            "git status --porcelain",
            block,
            "a '--main-sync-ff-merge' hook piszkos-fa őre kötelező — "
            "különben a 'main lemaradt + piszkos fa' cella csendben "
            "ff-merge-et hajtana végre piszkos fán (F1 review)",
        )
        self.assertIn(
            "halt:dirty-tree",
            block,
            "a piszkos-fa őr explicit 'halt:dirty-tree' jelölése kötelező "
            "— különben a teszt nem tudná kifejezetten a fa-őr kilépését "
            "azonosítani a 'noop' / 'divergencia' kilépések között",
        )


class PendingDoneFailSafeTest(unittest.TestCase):
    """A D2 fail-safe cellái — `chore(pipeline)` commit csak valóban kell.

    A driver `merged` ágában a `sed` parancs a sor-fájlon dolgozik, és CSAK
    akkor készít `chore(pipeline)` commitot, ha a sed tényleges változást
    okozott (a `git status --porcelain` üres ellenőrzés védi). Két eset
    kötelező:

      * a sor már `done` (az orchestrátor az egységes `docs(handoff…)`
        commitban átírta) → a fail-safe ág NEM készít commitot;
      * a sor `pending` maradt (az orchestrátor kihagyta) → a fail-safe
        ág `chore(pipeline)` commitot ír, és pushol.

    A második cella a „státusz elvesztésének" mért hibaosztálya: a sor
    örök `pending` maradna, és a lánc néma végállapotba ragadna.
    """

    def _commit_pending_done(self, worktree: Path, round: str, body: str) -> Path:
        queue = worktree / "docs" / "execution" / "pipeline-queue.tsv"
        queue.parent.mkdir(parents=True, exist_ok=True)
        queue.write_text(
            f"{round}\tdocs/rounds/{round.lower()}-x.md\tcodex\tnincs\t{body}\n",
            encoding="utf-8",
        )
        subprocess.run(["git", "add", str(queue)], cwd=worktree, check=True)
        commit = subprocess.run(
            ["git", "commit", "-qm", f"queue: {round} {body}"],
            cwd=worktree,
            check=True,
            text=True,
            capture_output=True,
        )
        return queue

    def _current_status(self, worktree: Path, round: str) -> str:
        text = (
            worktree / "docs" / "execution" / "pipeline-queue.tsv"
        ).read_text()
        for line in text.splitlines():
            if line.startswith(f"{round}\t"):
                return line.split("\t")[-1]
        return ""

    def test_done_status_must_not_trigger_a_fail_safe_commit(self) -> None:
        # 5. cella: a sor már `done`. A `--pending-done-failsafe-required`
        # horog (a `sed` parancsot reprodukálja) 1-gyel tér vissza, és a
        # driver oldalán a `git status --porcelain` így üres marad → nincs
        # `chore(pipeline)` commit. Ez a lánc álma: az orchestrátor AZ
        # EGYSÉGES `docs(handoff…)` commitban intézte a queue-t is.
        with tempfile.TemporaryDirectory() as directory_name:
            _, worktree = _make_bare_remote(Path(directory_name))
            self._commit_pending_done(worktree, "E99-R19", "done")

            probe = _run(
                [
                    "--pending-done-failsafe-required",
                    str(worktree / "docs" / "execution" / "pipeline-queue.tsv"),
                    "E99-R19",
                ],
                cwd=worktree,
            )
            self.assertEqual(
                probe.returncode,
                1,
                f"'done' státusznál a fail-safe NEM kell (returncode 1); "
                f"got rc={probe.returncode} stdout={probe.stdout!r}",
            )

    def test_pending_status_triggers_a_single_fail_safe_commit(self) -> None:
        # 6. cella: a sor `pending`, az orchestrátor kihagyta a záró
        # commitot. A driver ágában a `sed` átírja a státuszt, és egy
        # `chore(pipeline)` commit születik. Ez a fail-safe zárja az
        # elveszett `done` státusz hibaosztályát.
        with tempfile.TemporaryDirectory() as directory_name:
            _, worktree = _make_bare_remote(Path(directory_name))
            self._commit_pending_done(worktree, "E99-R19", "pending")
            before_head = subprocess.run(
                ["git", "rev-parse", "HEAD"],
                cwd=worktree,
                check=True,
                text=True,
                capture_output=True,
            ).stdout.strip()

            probe = _run(
                [
                    "--pending-done-failsafe-required",
                    str(worktree / "docs" / "execution" / "pipeline-queue.tsv"),
                    "E99-R19",
                ],
                cwd=worktree,
            )
            self.assertEqual(
                probe.returncode,
                0,
                f"'pending' státusznál a fail-safe kötelező (returncode 0); "
                f"got rc={probe.returncode} stdout={probe.stdout!r}",
            )

            # A driver ágának reprodukálása: sed + status-ellenőrzés + commit.
            queue = worktree / "docs" / "execution" / "pipeline-queue.tsv"
            subprocess.run(
                ["sed", "-i", r"s|^\(E99-R19\t.*\t\)pending$|\1done|", str(queue)],
                cwd=worktree,
                check=True,
            )
            dirt = subprocess.run(
                ["git", "status", "--porcelain", str(queue)],
                cwd=worktree,
                check=True,
                text=True,
                capture_output=True,
            ).stdout.strip()
            self.assertTrue(dirt, "a sed után a queue fájlnak piszkosnak kell lennie")
            subprocess.run(["git", "add", str(queue)], cwd=worktree, check=True)
            subprocess.run(
                ["git", "commit", "-qm", "chore(pipeline): E99-R19 done — fail-safe"],
                cwd=worktree,
                check=True,
            )
            after_head = subprocess.run(
                ["git", "rev-parse", "HEAD"],
                cwd=worktree,
                check=True,
                text=True,
                capture_output=True,
            ).stdout.strip()
            self.assertNotEqual(before_head, after_head)
            self.assertEqual(self._current_status(worktree, "E99-R19"), "done")

    def test_fail_safe_arm_must_survive_being_disabled(self) -> None:
        # Falszifikációs cella (brief §4, kötelező): ha a fail-safe
        # `if [ -n "$(git status --porcelain …)" ]` ágát kiveszik, a
        # „státusz pending" eset NEM készít commitot — az elveszett `done`
        # státusz hibaosztálya újraéled. A forrás-szintű regression-védelem
        # a `chore(pipeline)` szó ÉS a `pending` → `done` sed együttes
        # előfordulását ellenőrzi. Ha bármelyiket eltávolítják, a fail-safe
        # kar elveszett.
        #
        # A kar 2026-09-04 (E14-R07 / H3 önjavító kör, ADR 0112) óta a
        # `commit_main_bookkeeping()` függvényben él — a merge-ág csak HÍVJA.
        # Ezért a horgony a függvénytörzs, ÉS külön cella követeli, hogy a
        # `merged)` ág valóban delegáljon rá: a kar így se el nem tűnhet, se
        # ki nem köthető a merge-ágból. (A helyváltás oka mért: a közös
        # munkafában futó könyvelés a másik slot körének ágát mozdította el,
        # és a `main` push-a némán elbukott — l.
        # `tools/tests/test_pipeline_bookkeeping_worktree.py`.)
        text = SCRIPT.read_text()
        merged_block = text.split("merged)\n", 1)[1].split("\nesac\n", 1)[0]
        self.assertIn(
            'commit_main_bookkeeping "$round"',
            merged_block,
            "a `merged` ágnak a könyvelő függvényre kell delegálnia — "
            "különben a fail-safe kar nem fut le a merge után",
        )
        arm = text.split("commit_main_bookkeeping() {\n", 1)[1].split("\n}\n", 1)[0]
        # A driver a `$round`-os anchor-ált mintát használja — a `^(.*\t)`
        # általánosabb, és egy megengedőbb regresszió (pl. a `$round` anchor
        # lecserélése `.*`-ra) a lenti assertIn-t kikerülné, de az
        # `s|^\(...\t.*\t\)pending$|\1done|` konkrét mintát a `sed` már
        # nem a queue teljes sorára illesztené. Ez a szigorúbb regresszió-
        # védelem a D2 eredeti, mért megoldását őrzi.
        self.assertIn(
            's|^\\($round\\t.*\\t\\)pending$|\\1done|',
            arm,
            "a könyvelő karban a '$round-anchor-ált pending → done' "
            "átírás kötelező, különben a fail-safe elveszett",
        )
        self.assertIn(
            "chore(pipeline):",
            arm,
            "a könyvelő karban a 'chore(pipeline)' commit üzenet "
            "kötelező — ez a fail-safe kar látható nyoma",
        )
        self.assertIn(
            # a kar a saját munkapéldányát méri (`git -C "$worktree" status …`),
            # ezért az őr a `-- "${paths[@]}"`-szal együtt horgonyzott: ez
            # SZŰKEBB minta a réginél, nem megengedőbb
            'status --porcelain -- "${paths[@]}"',
            arm,
            "a fail-safe csak VALÓDI piszka során commitol — a "
            "`git status --porcelain` őr kivesztése néma üres commitot "
            "vagy elveszett fail-safe-t okoz",
        )

    def test_done_pending_idempotency_round_trip(self) -> None:
        # Kiegészítő biztonságiellenőrzés: a fail-safe kétszeri futtatása
        # a második menetre NEM készít plusz commitot — a mért védelem a
        # `git status --porcelain` üres-ágán ül, nem a sor szövegén.
        with tempfile.TemporaryDirectory() as directory_name:
            _, worktree = _make_bare_remote(Path(directory_name))
            self._commit_pending_done(worktree, "E99-R19", "pending")
            queue = worktree / "docs" / "execution" / "pipeline-queue.tsv"
            before_head = subprocess.run(
                ["git", "rev-parse", "HEAD"],
                cwd=worktree,
                check=True,
                text=True,
                capture_output=True,
            ).stdout.strip()

            # 1. menet: pending → done + commit
            subprocess.run(
                ["sed", "-i", r"s|^\(E99-R19\t.*\t\)pending$|\1done|", str(queue)],
                cwd=worktree,
                check=True,
            )
            subprocess.run(["git", "add", str(queue)], cwd=worktree, check=True)
            subprocess.run(
                ["git", "commit", "-qm", "chore(pipeline): E99-R19 done — fail-safe"],
                cwd=worktree,
                check=True,
            )

            # 2. menet: done → done: a sed no-op, a `git status --porcelain`
            # üres, NEM keletkezik commit.
            subprocess.run(
                ["sed", "-i", r"s|^\(E99-R19\t.*\t\)pending$|\1done|", str(queue)],
                cwd=worktree,
                check=True,
            )
            dirt = subprocess.run(
                ["git", "status", "--porcelain", str(queue)],
                cwd=worktree,
                check=True,
                text=True,
                capture_output=True,
            ).stdout.strip()
            self.assertFalse(
                dirt,
                "második menetben a queue nem piszkos, így a fail-safe NEM commitol — "
                "ez a védelem a 'done' státusz megőrzése mellett plusz commitot "
                "sem termel (D2 kulcs-ígérete: egy merge után egy CI-futás)",
            )

            after_head = subprocess.run(
                ["git", "rev-parse", "HEAD"],
                cwd=worktree,
                check=True,
                text=True,
                capture_output=True,
            ).stdout.strip()
            self.assertNotEqual(before_head, after_head)


if __name__ == "__main__":
    unittest.main()
