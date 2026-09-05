import json
import os
import re
import shutil
import subprocess
import tempfile
import time
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]

# Valódi, mért adat (E05-R15 H6 önjavítás, 2026-08-07T16:46:20Z): a
# .pipeline/HALTED tényleges `summary=` mezőjének verbatim másolata, a Codex
# CLI upstream usage-limit falába ütköző fix-round-2 után. A hármas
# "usage limit... try again at Aug 8th, 2026 7:32 AM" hibaszöveg a
# /tmp/codex-e05-r15-fix2b.log nyers kimenetéből származik (3x azonos, a
# kezdő kísérlet + 2 automatikus folytatás).
REAL_E05_R15_CODEX_USAGE_LIMIT_SUMMARY = (
    'Codex/Terra (gpt-5.6-terra) quota exhausted mid-fix-round-2 (initial '
    'attempt + 2 auto-continuations all hit an identical "usage limit... '
    'try again at Aug 8th, 2026 7:32 AM" error) — not a code defect or '
    "capability failure. MAJOR-1 and MAJOR-2 are closed and independently "
    "re-verified; BLOCKER-1's root cause is fully diagnosed with a "
    "mathematically validated fix (0 false negatives across two independent "
    "50k-trial adversarial searches) ready to implement, just blocked on "
    "Codex compute availability."
)
# A szövegben ténylegesen kódolt reset-időpont (Aug 8th, 2026 7:32 AM, UTC —
# a box órája és a HALTED `halted_at` mezője is UTC) epoch-alakban.
REAL_E05_R15_CODEX_USAGE_LIMIT_RESET_EPOCH = 1786174320


class PipelineIntegrationTest(unittest.TestCase):
    def run_command(self, argv, *, cwd=ROOT, env=None):
        # A driver GitHub-incidens őre (`github_actions_degraded`) ÉLŐ HTTP-hívás
        # a githubstatus.com-ra, és incidens alatt RÖVIDRE ZÁRJA a self-heal ágat
        # („az önjavítás KIMARAD: GitHub Actions incidens alatt a halt oka
        # külső"). Egy tesztnek SOHA nem szabad külső szolgáltatás pillanatnyi
        # állapotától függenie.
        #
        # MÉRT eset (2026-08-26, E13-R24/H5): a GitHub Actions `major_outage`
        # alatt a Router CI ezen a fájlon 4 cellát bukott — `..._starts_selfheal_
        # unless_it_is_switched_off`, `..._gives_up_after_the_configured_attempt_
        # budget`, `..._registers_and_clears_its_own_inflight_marker`,
        # `..._skips_a_round_that_already_has_an_active_heal_session` —, mind
        # azonos okkal: az őr elnyelte azt az ágat, amit a cella épp mér. A kör
        # diffje ezt a fájlt nem is érintette (scope-audit OK), tehát a piros oka
        # 100%-ban külső volt, és a KÉSZ + APPROVED kör merge-e emiatt állt meg.
        #
        # A driver már hordozza a kikapcsolót (`PIPELINE_STATUS_CHECK`, 2026-08-06),
        # csak ez a suite nem használta — a `test_engine_override_ttl.py` igen, az
        # a precedens. `setdefault`, nem felülírás: egy cella, ami épp az őrt
        # méri, továbbra is beállíthatja explicit `"1"`-re.
        if env is not None:
            env.setdefault("PIPELINE_STATUS_CHECK", "0")
        return subprocess.run(
            argv,
            cwd=cwd,
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )

    def test_the_selfheal_path_survives_a_live_github_actions_outage(self) -> None:
        """A self-heal ág GitHub-incidens alatt is mérhető marad.

        A cella a `major_outage`-ot HAMISÍTJA (fake `curl` a PATH elején), tehát
        nem a valódi GitHub-állapottól függ — se zöld, se piros napon nem
        billen. Az `PIPELINE_STATUS_CHECK=0` nélkül a driver itt az „önjavítás
        KIMARAD" ágra menne, és a `run_command` alapértéke épp ezt zárja ki.
        """
        script = ROOT / "tools" / "round-pipeline.sh"
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            state = directory / "state"
            state.mkdir()
            fake_bin = directory / "bin"
            fake_bin.mkdir()
            curl = fake_bin / "curl"
            curl.write_text(
                "#!/bin/sh\n"
                'printf \'{"components": [{"name": "Actions", "status": "major_outage"}]}\'\n'
            )
            curl.chmod(0o755)
            (state / "HALTED").write_text("round=E09-R01\nhalt=H6\nsummary=teszt halt\n")
            env = dict(os.environ)
            env.update(
                PIPELINE_STATE_DIR=str(state),
                PIPELINE_SELFHEAL="0",
                PIPELINE_NO_LAUNCH="1",
                PATH=f"{fake_bin}:{env['PATH']}",
            )

            result = self.run_command(["bash", str(script)], env=env)

            self.assertNotIn(
                "az önjavítás KIMARAD",
                result.stderr,
                "a hamisított GitHub-incidens elnyelte a self-heal ágat — a "
                "suite külső szolgáltatás pillanatnyi állapotától függ",
            )
            self.assertIn("önjavítás kikapcsolva", result.stderr)
            self.assertEqual(result.returncode, 3)

    def test_a_cell_may_still_opt_into_the_live_incident_guard(self) -> None:
        """A `setdefault` nem vesz el képességet: explicit `"1"` visszahozza az őrt."""
        script = ROOT / "tools" / "round-pipeline.sh"
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            state = directory / "state"
            state.mkdir()
            fake_bin = directory / "bin"
            fake_bin.mkdir()
            curl = fake_bin / "curl"
            curl.write_text(
                "#!/bin/sh\n"
                'printf \'{"components": [{"name": "Actions", "status": "major_outage"}]}\'\n'
            )
            curl.chmod(0o755)
            (state / "HALTED").write_text("round=E09-R01\nhalt=H6\nsummary=teszt halt\n")
            env = dict(os.environ)
            env.update(
                PIPELINE_STATE_DIR=str(state),
                PIPELINE_SELFHEAL="1",
                PIPELINE_NO_LAUNCH="1",
                PIPELINE_STATUS_CHECK="1",
                PATH=f"{fake_bin}:{env['PATH']}",
            )

            result = self.run_command(["bash", str(script)], env=env)

            self.assertIn("az önjavítás KIMARAD", result.stderr)

    def test_engine_enum_accepts_auto_and_keeps_legacy_overrides(self) -> None:
        script = ROOT / "tools" / "round-pipeline.sh"
        # A `terra` a nyilvántartás sora (ADR 0140): a queue is hivatkozhat rá
        # (user-döntés 2026-08-20 — Pro-keret égetése, minden nyitott sor terra).
        for engine in ("auto", "minimax", "codex", "terra"):
            with self.subTest(engine=engine):
                result = self.run_command(["bash", str(script), "--validate-engine", engine])
                self.assertEqual(result.returncode, 0, result.stderr)
        rejected = self.run_command(["bash", str(script), "--validate-engine", "surprise"])
        self.assertEqual(rejected.returncode, 2)

    def test_queue_runs_the_whole_epic3_continuously_including_the_closure_round(self) -> None:
        # A user 2026-08-01-i döntése: az Epic 3 MIND a 22 sora fut
        # folyamatosan, kézi zárókör nélkül. (A korábbi `prepared` + kézi
        # zárókör elvárását ez váltotta le — ADR 0087 §7, ADR 0112 §6.)
        #
        # Módosítás 2026-08-04 (user-döntés: „a fejlesztő legyen a Terra"): a
        # MÉG NYITOTT sorok implementer-motorja `auto` (MiniMax-first router)
        # helyett a kétmotoros szabály szerinti Terra/M3 — lásd
        # test_open_rounds_follow_the_measured_engine_rule. A lezárt sorok
        # `auto` értéke történeti tény, nem írjuk át. A folyamatosság elvárása
        # változatlan.
        queue = (ROOT / "docs" / "execution" / "pipeline-queue.tsv").read_text()
        self.assertIn("auto | minimax | codex", queue)
        rows = [line.split("\t") for line in queue.splitlines() if line and not line.startswith("#")]
        # `terra` a 2026-08-20-i user-döntés (Pro-keret égetése) queue-értéke.
        # `sonnet-impl` 2026-08-23-tól (user-döntés): a Chapter 13 UI-sáv
        # implementere a natív Claude Sonnet 5, Opus 5 orchestrátor alatt.
        self.assertTrue(
            all(row[2] in {"auto", "minimax", "codex", "terra", "sonnet-impl"} for row in rows)
        )
        epic3 = [row for row in rows if row[0].startswith("E03-")]
        self.assertEqual([row[0] for row in epic3], [f"E03-R{i:02d}" for i in range(1, 23)])
        self.assertTrue(all(row[4] in {"pending", "running", "done"} for row in epic3))
        self.assertTrue(all(row[2] in {"codex", "minimax"} for row in epic3 if row[4] != "done"))

    def test_open_rounds_follow_the_measured_engine_rule(self) -> None:
        """A nyitott körök motorja a brief MÉRT mezőiből számolt, nem becslés.

        User-döntés 2026-08-04: „bizonyos feladatokhoz a MiniMax M3 is
        beállítható, amikor a Terránál jobban teljesít." A szabály (ADR 0069
        mért motor-szétosztása alapján):

          risk == "normal"                            → minimax  (volumenkör)
          risk == "high" ÉS UI/ARB > domain+app+data  → minimax  (UI-dominált)
          egyébként                                   → codex    (Terra)

        A teszt a queue-t a briefekhez KÖTI, így egy új brief hozzáadásakor a
        motorválasztás nem maradhat kézi becslés. A védőháló változatlan: a
        kör-gate, az Opus 4.8 független review és a CI mindkét motorra ugyanaz.

        A szabály NEM epic-specifikus: minden MÉG NYITOTT sorra érvényes,
        bármelyik epicből (E03 lezárult 2026-08-04-én, a nyitott sorok azóta
        E04-esek). A korábbi `E03-` szűrő beragadt: az Epic 3 zárásával a lista
        kiürült, és a `test_all_twenty_two_briefs...` melletti üres-lista
        assertion nyolc körön át pirosra állította a Router CI-t (mérve
        2026-08-05, E04-R07 után). Ezért a filter epic-agnosztikus.
        """
        queue_path = ROOT / "docs" / "execution" / "pipeline-queue.tsv"
        rows = [
            line.split("\t")
            for line in queue_path.read_text().splitlines()
            if line and not line.startswith("#")
        ]
        self.assertTrue(rows, "a sor-fájl üres vagy nem parse-olható — ez VALÓDI hiba")
        open_rounds = [row for row in rows if row[4] != "done"]
        if not open_rounds:
            # MÉRT hiba (2026-08-14, az Epic 6 lezárása; másodszor — először
            # 2026-08-05, E04-R07 után nyolc körön át): a kiürült sor NEM
            # defekt, hanem LEGITIM állapot — épp befejeztünk egy epicet, és a
            # következő irány emberi döntés (ADR 0087 §7). A korábbi
            # `assertTrue(open_rounds)` viszont ilyenkor pirosra állította a
            # main-t, a `round-pipeline.sh:1584` main-health kapuja pedig nem
            # indít munkát piros main fölé -> a lánc MAGÁRA ZÁRTA az ajtót, és
            # csak emberi észrevétel oldotta fel (6 óra állás).
            #
            # A mérce NEM gyengül: minden NYITOTT kört ugyanúgy mér a lenti
            # ciklus; csak azt ismerjük el, hogy nulla nyitott körön nincs mit
            # mérni. A fenti `rows` assert megkülönbözteti a legitim üres sort
            # (minden sor `done`) a sérült/üres fájltól.
            self.skipTest("a sor kiürült (minden kör `done`) — epic-határ, emberi döntésre vár")

        for round_id, brief, engine, _adr, _status in open_rounds:
            with self.subTest(round=round_id):
                # USER-DÖNTÉS 2026-08-21 („lejárt a GPT kvóta"): a
                # Codex-oldal (`codex`/`terra`/`sol`, mind a gpt-5.6-* család,
                # közös elfogyott előfizetés) NEM futtatható, tehát a mért
                # szabály `codex` ága erre az időszakra FELFÜGGESZTVE — az
                # egyetlen elérhető implementer a `minimax`.
                #
                # A cella ettől NEM lesz vak, mert két dolgot továbbra is mér:
                #   (a) nyitott sor Codex-oldali motort NEM nevezhet meg (lásd
                #       a ciklus utáni assertet) — egy új `codex`/`terra` sor
                #       azonnal pirosra vált;
                #   (b) a pin CSAK `codex` → `minimax` irányba mozdulhat: ahol
                #       a mért szabály `minimax`-ot ad, ott `minimax`-nak KELL
                #       állnia, tehát a szabály minimax-ága változatlanul él.
                # A Codex-előfizetés újraéledésekor ez a carve-out törlendő, és
                # a nyitott sorokat a mért szabály szerint kell visszaosztani.
                text = (ROOT / brief).read_text()
                risk = re.search(r'^risk\s*=\s*"(\w+)"', text, re.M)
                self.assertIsNotNone(risk, f"{brief}: nincs risk mező")
                block = re.search(r"allowed_paths\s*=\s*\[(.*?)\]", text, re.S)
                self.assertIsNotNone(block, f"{brief}: nincs allowed_paths")
                paths = re.findall(r'"([^"]+)"', block.group(1))
                ui = sum(1 for p in paths if "/presentation/" in p or p.endswith(".arb"))
                core = sum(
                    1
                    for p in paths
                    if any(segment in p for segment in ("/domain/", "/application/", "/data/"))
                )
                expected = "minimax" if (risk.group(1) == "normal" or ui > core) else "codex"
                allowed = {"minimax"} if expected == "minimax" else {"minimax", "codex"}
                # USER-DÖNTÉS 2026-08-23: a Chapter 13 (UI/UX design system)
                # sáv implementere a `sonnet-impl` (natív Claude Sonnet 5,
                # `--effort high`), fölötte Opus 5 orchestrátor (effort
                # 2026-08-25 óta `high`, heti-keret mérés). Indok: a
                # MiniMax MÉRT gyengéje az invariáns-lazítás (engine-registry),
                # a Ch13-körök mércéje viszont épp invariáns-sűrű (kontraszt-őr,
                # text-scale mátrix, a11y-szerződés). A carve-out SZŰK: csak az
                # E13-sávra, csak `sonnet-impl` irányba, és a Codex-oldali
                # tiltás (lásd a ciklus utáni assertet) változatlanul él.
                #
                # USER-DÖNTÉS 2026-08-27 (a Ch13 sáv lezárása után): a Chapter 12
                # (Release Roadmap & Final Integration) sáv UGYANEZZEL a
                # felállással indul — implementer `sonnet-impl`, orchestrátor
                # Opus 5 `--effort high` —, ezért a carve-out az `E12-` előtagra
                # is szól. Indok azonos: a Ch12-körök mércéje invariáns-sűrű
                # (fail-closed konfiguráció, signing, consent-kényszerítés,
                # release-kapuk), és a MiniMax MÉRT gyengéje épp az
                # invariáns-lazítás. A carve-out továbbra is SZŰK: két nevesített
                # sáv, csak `sonnet-impl` irányba, a Codex-oldali tiltás él.
                # USER-DÖNTÉS 2026-08-28: a Chapter 15 (UI-aktiválás és
                # -befejezés) sáv ugyanezzel a felállással fut a MÁSODIK
                # sloton — implementer `sonnet-impl`, orchestrátor Opus 5.
                # Indok azonos: a Ch15-körök mércéje invariáns-sűrű (típus-
                # pinnelő őrök, text-scale mátrix, a11y-szerződés, backend
                # kapu-cellák).
                # USER-DÖNTÉS 2026-09-02: a Chapter 16 (Kompozíció és rollout)
                # sáv ugyanezzel a felállással fut — implementer `sonnet-impl`,
                # orchestrátor Opus 5.
                # 2026-09-04: a Chapter 14 (felismerési pontosság) sáv
                # visszakapcsolásakor ugyanez a felállás. Indok MÉRT és
                # erősebb, mint a többi sávnál: az E14 munkája maga a MÉRÉS
                # (küszöbök, baseline-ok, A/B-harness), ahol a MiniMax mért
                # gyengéje — az invariáns-lazítás — pontosan a mércét rontaná
                # el. A minimax elérhető marad (99% heti keret), a sáv rá
                # visszaváltható, ha a Claude-keret szűkül.
                # USER-DÖNTÉS 2026-09-05: „ne minimaxal fusson, minden fusson
                # Sonnet 5 high-al és Opus 5 orchestrátorral." A carve-out
                # ezzel megszűnik sáv-listának lenni: MINDEN nyitott kör
                # mehet `sonnet-impl`-re. Indok — a korábbi sáv-bővítések
                # indoklása általánosodott: a MiniMax MÉRT gyengéje az
                # invariáns-lazítás (engine-registry: „9/10; mért gyengéje:
                # invariánst lazít"), a hátralévő mezőny (E17 bekötési sáv,
                # E09/E10 sávok) mércéje viszont végig invariáns-sűrű —
                # típus-pinnelő őrök, gate-cellák, fail-closed kapuk.
                #
                # A `minimax` NEM tiltott: a `expected` szabály változatlanul
                # kiszámolódik, és a minimax mindkét ágon `allowed` marad,
                # tehát a sor bármikor visszaállítható rá (pl. ha a Claude
                # heti keret szűkül). Ami megszűnt, az a sáv-előtag
                # feltétele — nem a mért motor-szabály.
                #
                # A Codex-oldali tiltás (a ciklus utáni assert) VÁLTOZATLAN.
                allowed = allowed | {"sonnet-impl"}
                self.assertIn(
                    engine,
                    allowed,
                    f"{round_id}: risk={risk.group(1)} UI/ARB={ui} core={core} → {expected}; "
                    "a Codex-kimaradás alatt a pin CSAK codex→minimax (E13-en "
                    "codex→minimax|sonnet-impl) irányba mozdulhat",
                )

        # (a) A kimaradás alatt egyetlen NYITOTT sor sem nevezhet meg
        # Codex-oldali motort — ez a carve-out fail-closed párja.
        codex_side = {row[0]: row[2] for row in open_rounds if row[2] in {"codex", "terra", "sol"}}
        self.assertEqual(
            codex_side,
            {},
            "a GPT-kvóta elfogyott (user-döntés 2026-08-21): nyitott sor nem mehet "
            "Codex-oldali motorra — a mezőny egyetlen elérhető implementere a `minimax`",
        )

    def test_prompt_has_one_initial_auto_dispatch_and_budget_preserving_resume(self) -> None:
        prompt = (ROOT / "docs" / "execution" / "pipeline-orchestrator-prompt.md").read_text()
        self.assertEqual(prompt.count("ai-router-round.sh run"), 1)
        self.assertIn("ai-router-round.sh resume", prompt)
        self.assertIn("READY_FOR_REVIEW", prompt)
        self.assertIn("független", prompt.lower())
        self.assertIn("review + CI", prompt)
        self.assertIn("örökölt", prompt.lower())

    def test_post_merge_gate_bootstraps_ignored_flutter_generated_output(self) -> None:
        # E03-R14/H7 (2026-08-03): PR #107 merged ARB keys, but the
        # post-merge gate used the old ignored AppLocalizations output and
        # reported six missing getters. The bootstrap must precede that gate;
        # otherwise a clean checkout can fail with hundreds of missing imports.
        prompt = (ROOT / "docs" / "execution" / "pipeline-orchestrator-prompt.md").read_text()
        preparation = "tools/prepare-flutter-generated.sh"
        gate = "tools/round-gate.sh"

        self.assertIn(preparation, prompt)
        self.assertIn(gate, prompt)
        self.assertLess(prompt.index(preparation), prompt.rindex(gate))

    def test_prompt_auto_dispatch_is_detached_and_polled_not_synchronous(self) -> None:
        # Módosítás (ADR 0112 önjavító kör, 2026-08-02, E03-R05 H6): a
        # `engine=auto` dispatch a Bash-eszköz mért 600s-es kemény plafonjánál
        # rövidebbre volt kényszerítve egy szinkron hívással, miközben
        # `.ai/router.toml`-ban `model_timeout_seconds=7200` — két egymást
        # követő hívás mindkétszer SIGTERM-mel halt meg jelzés nélkül
        # (docs/LESSONS.md L42 pontos ismétlődése). A javítás a már
        # `minimax`/`codex` úton szentesített leválaszt-és-előtérben-várj
        # mintát vezeti be `auto`-ra is. Ez a teszt a REGRESSZIÓ ellen véd:
        # a szinkron parancs visszaállítása ne csússzon be észrevétlenül.
        prompt = (ROOT / "docs" / "execution" / "pipeline-orchestrator-prompt.md").read_text()
        auto_section = prompt.split("### `auto`", 1)[1].split("### `minimax`", 1)[0]
        self.assertIn("setsid", auto_section)
        self.assertIn("wait-for-router.sh", auto_section)
        self.assertNotIn("előtérben, szinkron módon", prompt)
        self.assertTrue((ROOT / "tools" / "wait-for-router.sh").exists())

    def make_router_signal_worktree(self, directory: Path) -> Path:
        worktree = directory / "signal-worktree"
        (worktree / "tools").mkdir(parents=True)
        shutil.copy2(ROOT / "tools" / "codex-signal.sh", worktree / "tools" / "codex-signal.sh")
        subprocess.run(["git", "init", "-q"], cwd=worktree, check=True)
        subprocess.run(["git", "config", "user.email", "pipeline@example.invalid"], cwd=worktree, check=True)
        subprocess.run(["git", "config", "user.name", "Pipeline Test"], cwd=worktree, check=True)
        (worktree / "readme.txt").write_text("signal fixture\n")
        subprocess.run(["git", "add", "."], cwd=worktree, check=True)
        subprocess.run(["git", "commit", "-qm", "baseline"], cwd=worktree, check=True)
        return worktree

    def test_wait_for_round_does_not_recognize_router_terminal_signals(self) -> None:
        # A MÉRT gyökérok, ami miatt `wait-for-router.sh` külön szkript kell:
        # az örökölt `wait-for-round.sh` `case`-ága nem ismeri a router
        # `progress`/`blocked` állapotait, tehát azokra a `max_wait` leteltéig
        # üresen pörögne -- ha ezt valaha megoldanák `wait-for-round.sh`
        # bővítésével, ez a teszt jelezze, mert akkor `wait-for-router.sh`
        # feleslegessé válhat, de a mostani, MÉRT viselkedés ez. A jelzést a
        # VÁRAKOZÁS INDULÁSA UTÁN írjuk (Popen), mert a valós futásban is így
        # történik -- előbb írva a baseline-védelem (L12) takarná el a
        # `case`-ág hiányát.
        with tempfile.TemporaryDirectory() as directory_name:
            worktree = self.make_router_signal_worktree(Path(directory_name))
            env = dict(os.environ, WAIT_POLL_SECONDS="1")
            process = subprocess.Popen(
                ["bash", str(ROOT / "tools" / "wait-for-round.sh"), str(worktree), "3"],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env=env,
            )
            time.sleep(1)
            script = worktree / "tools" / "codex-signal.sh"
            self.run_command(["bash", str(script), "READY_FOR_REVIEW", "router done"], cwd=worktree)
            stdout, stderr = process.communicate(timeout=10)

            self.assertEqual(process.returncode, 5, stdout + stderr)
            self.assertIn("MÉG FUTHAT", stderr)

    def test_wait_for_router_recognizes_every_terminal_router_status_promptly(self) -> None:
        for router_status in ("READY_FOR_REVIEW", "STOPPED", "DEFERRED", "BLOCKED", "INTERNAL_ERROR"):
            with self.subTest(router_status=router_status):
                with tempfile.TemporaryDirectory() as directory_name:
                    worktree = self.make_router_signal_worktree(Path(directory_name))
                    env = dict(os.environ, WAIT_POLL_SECONDS="1")
                    process = subprocess.Popen(
                        ["bash", str(ROOT / "tools" / "wait-for-router.sh"), str(worktree), "10"],
                        text=True,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                        env=env,
                    )
                    time.sleep(1)
                    script = worktree / "tools" / "codex-signal.sh"
                    self.run_command(["bash", str(script), router_status, "router terminal"], cwd=worktree)
                    stdout, stderr = process.communicate(timeout=10)

                    self.assertEqual(process.returncode, 0, stdout + stderr)
                    self.assertIn(f"router_status={router_status}", stdout)

    def test_wait_for_router_times_out_while_the_router_is_still_running(self) -> None:
        with tempfile.TemporaryDirectory() as directory_name:
            worktree = self.make_router_signal_worktree(Path(directory_name))

            completed = self.run_command(
                ["bash", str(ROOT / "tools" / "wait-for-router.sh"), str(worktree), "2"],
            )

            self.assertEqual(completed.returncode, 5, completed.stdout + completed.stderr)
            self.assertIn("MÉG FUTHAT", completed.stderr)

    def test_wait_for_router_ignores_a_stale_terminal_signal_from_a_previous_round(self) -> None:
        # Ugyanaz a védelem, mint wait-for-round.sh-nál: egy korábbi kör
        # bennragadt terminális jelzése ne zárja le azonnal az új várakozást.
        with tempfile.TemporaryDirectory() as directory_name:
            worktree = self.make_router_signal_worktree(Path(directory_name))
            script = worktree / "tools" / "codex-signal.sh"
            self.run_command(["bash", str(script), "STOPPED", "stale from a previous round"], cwd=worktree)

            completed = self.run_command(
                ["bash", str(ROOT / "tools" / "wait-for-router.sh"), str(worktree), "2"],
            )

            self.assertEqual(completed.returncode, 5, completed.stdout + completed.stderr)

    def test_wait_for_round_recognizes_a_completion_signalled_between_two_fresh_polls(self) -> None:
        # MÉRT gyökérok (E07-R19, H-NOSIGNAL önjavítás, 2026-08-18, session
        # rollout `01a014b9-af37-7033-8ced-28b00e8f7116`): a Terra
        # orchestrátor `exec_command`/`wait` harnessje csendes parancsnál
        # önmagától „yield"-el, ezért a dokumentált „exit 5 -> hívd meg újra"
        # szerződés szerint ezt a scriptet NEM egyetlen hosszan futó
        # hívásként indította, hanem ~20, egyenként friss folyamatként (cell
        # ID 65..87). A javítás ELŐTT minden friss folyamat a SAJÁT indulási
        # pillanatában újraszámolta a baseline-t a jelzésfájl AKKORI
        # tartalmából, ezért egy, a tényleges befejezés UTÁN induló friss
        # hívás a friss `done`-t tekintette baseline-nak, és sosem jelentette
        # késznek. Élesben `.codex-round-status` `status=done` (a Codex-javító
        # kör commitolva és pusholva, gate zöld) már 12:30:06Z-kor készen
        # állt, az orchestrátor mégis 12:37:08-ig, 7 percen át üres kimenetet
        # kapott minden friss hívástól, majd jelzés nélkül elfogyott a turnja
        # (H-NOSIGNAL) -- a kész munka a branchen vesztegelt.
        #
        # Ez a teszt pontosan ezt a rést reprodukálja: az ELSŐ hívás (még
        # nincs jelzés) megalapozza a baseline-t és lejár; a jelzés a hívások
        # KÖZÖTT érkezik (nem a várakozás alatt); a MÁSODIK, teljesen friss
        # folyamat kell, hogy azonnal felismerje.
        with tempfile.TemporaryDirectory() as directory_name:
            worktree = self.make_router_signal_worktree(Path(directory_name))
            env = dict(os.environ, WAIT_POLL_SECONDS="1")

            first = self.run_command(
                ["bash", str(ROOT / "tools" / "wait-for-round.sh"), str(worktree), "2"],
                env=env,
            )
            self.assertEqual(first.returncode, 5, first.stdout + first.stderr)

            script = worktree / "tools" / "codex-signal.sh"
            self.run_command(["bash", str(script), "done", "repair committed and pushed"], cwd=worktree)

            second = self.run_command(
                ["bash", str(ROOT / "tools" / "wait-for-round.sh"), str(worktree), "5"],
                env=env,
            )
            self.assertEqual(second.returncode, 0, second.stdout + second.stderr)
            self.assertIn("status=done", second.stdout)

    def test_wait_for_router_recognizes_a_completion_signalled_between_two_fresh_polls(self) -> None:
        # Ugyanaz a rés, ugyanaz a javítás, mint wait-for-round.sh-nál: a
        # router-oldali várakoztató a `.codex-round-status` UGYANAZT a
        # `signalled_at` baseline-mechanizmust örökli, tehát ugyanígy vak
        # marad egy, a tényleges befejezés UTÁN induló friss hívásban.
        with tempfile.TemporaryDirectory() as directory_name:
            worktree = self.make_router_signal_worktree(Path(directory_name))
            env = dict(os.environ, WAIT_POLL_SECONDS="1")

            first = self.run_command(
                ["bash", str(ROOT / "tools" / "wait-for-router.sh"), str(worktree), "2"],
                env=env,
            )
            self.assertEqual(first.returncode, 5, first.stdout + first.stderr)

            script = worktree / "tools" / "codex-signal.sh"
            self.run_command(["bash", str(script), "READY_FOR_REVIEW", "router done"], cwd=worktree)

            second = self.run_command(
                ["bash", str(ROOT / "tools" / "wait-for-router.sh"), str(worktree), "5"],
                env=env,
            )
            self.assertEqual(second.returncode, 0, second.stdout + second.stderr)
            self.assertIn("router_status=READY_FOR_REVIEW", second.stdout)

    def test_wait_for_round_still_ignores_a_delivered_signal_once_a_new_wait_begins(self) -> None:
        # Nem-regressziós társteszt: az EREDETI védelem (E02-R08 resume, a
        # fájl tetején lévő header) nem sérülhet a fenti javítástól. Az ELSŐ
        # várakozás a valódi dispatch-mintát követi (a hívás baseline-ja MÉG
        # üres, a jelzés a várakozás ALATT érkezik -- ugyanaz a Popen-minta,
        # mint `test_wait_for_round_does_not_recognize_router_terminal_signals`-
        # nál) és helyesen kézbesíti a `stopped`-ot. Ha egy terminális jelzést
        # már KÉZBESÍTETTÜNK egy hívónak, egy azt KÖVETŐ, teljesen új
        # várakozás ne jelentse azonnal késznek ugyanazt a még mindig ott ülő,
        # régi jelzést -- a marker a kézbesítéskor törlődik, az új várakozás
        # pedig a jelenlegi (régi) tartalmat veszi fel új baseline-nak, ahogy
        # a javítás előtt is tette.
        with tempfile.TemporaryDirectory() as directory_name:
            worktree = self.make_router_signal_worktree(Path(directory_name))
            env = dict(os.environ, WAIT_POLL_SECONDS="1")
            script = worktree / "tools" / "codex-signal.sh"

            first = subprocess.Popen(
                ["bash", str(ROOT / "tools" / "wait-for-round.sh"), str(worktree), "10"],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env=env,
            )
            time.sleep(1)
            self.run_command(["bash", str(script), "stopped", "decision needed"], cwd=worktree)
            stdout, stderr = first.communicate(timeout=10)
            self.assertEqual(first.returncode, 3, stdout + stderr)

            second = self.run_command(
                ["bash", str(ROOT / "tools" / "wait-for-round.sh"), str(worktree), "2"],
                env=env,
            )
            self.assertEqual(second.returncode, 5, second.stdout + second.stderr)

    def test_selfheal_prompt_defines_the_three_outcomes_and_the_gate_boundary(self) -> None:
        prompt = (ROOT / "docs" / "execution" / "pipeline-selfheal-prompt.md").read_text()
        for placeholder in ("{{ROUND}}", "{{HALT_CODE}}", "{{ATTEMPT}}", "{{HEAL_STATUS_FILE}}"):
            self.assertIn(placeholder, prompt)
        for outcome in ("outcome=fixed", "`retry`", "`escalate`"):
            self.assertIn(outcome, prompt)
        # A mérce-határ nem opcionális része a promptnak (ADR 0112 §3).
        self.assertIn("round-gate.sh", prompt)
        self.assertIn(".github/workflows/", prompt)
        self.assertIn("regressziós teszt", prompt)

    def test_selfheal_prompt_preserves_current_main_scope_for_h8_brief_conflicts(self) -> None:
        """H8 regression: a superseded round brief must not require a force-push."""
        prompt = (ROOT / "docs" / "execution" / "pipeline-selfheal-prompt.md").read_text()
        self.assertIn("H8", prompt)
        self.assertIn("rebase --abort", prompt)
        self.assertIn("merge --no-ff origin/main", prompt)
        self.assertIn("merge-base --is-ancestor origin/main HEAD", prompt)
        self.assertIn("force-push", prompt)
        self.assertIn("aktuális `main` brief-változatát", prompt)
        # E08-R12/H8: the rebase had already completed before safe-force-push
        # exposed remote-only merge commits plus the superseded pre-flight.
        # Recovery must preserve both heads until byte-identical trees prove
        # that a normal merge loses neither the product diff nor current scope.
        self.assertIn("safe-force-push", prompt)
        self.assertIn("branch backup/<kör>-pre-h8 HEAD", prompt)
        self.assertIn("switch --detach origin/<kör-branch>", prompt)
        self.assertIn("diff --exit-code backup/<kör>-pre-h8 HEAD", prompt)
        self.assertIn("remote-only listán", prompt)
        adr = (ROOT / "docs" / "adr" / "0112-self-healing-pipeline.md").read_text()
        self.assertIn("merge-base --is-ancestor origin/main HEAD", adr)

    def test_selfheal_prompt_recovers_a_stale_h6_baseline_before_router_resume(self) -> None:
        """H6 regression: merged heal commits must not be audited as model changes."""
        prompt = (ROOT / "docs" / "execution" / "pipeline-selfheal-prompt.md").read_text()
        self.assertIn("rebase-baseline --task {{ROUND}} --worktree <kör-worktree>", prompt)
        self.assertIn("READY_FOR_REVIEW", prompt)
        self.assertIn("kézi\nJSON-szerkesztés", prompt)
        self.assertIn("state-reset", prompt)

    def test_halted_chain_starts_selfheal_unless_it_is_switched_off(self) -> None:
        script = ROOT / "tools" / "round-pipeline.sh"
        with tempfile.TemporaryDirectory() as directory_name:
            state = Path(directory_name)
            (state / "HALTED").write_text("round=E09-R01\nhalt=H6\nsummary=teszt halt\n")
            env = dict(os.environ)
            env.update(
                PIPELINE_STATE_DIR=str(state),
                PIPELINE_SELFHEAL="0",
                PIPELINE_NO_LAUNCH="1",
            )

            switched_off = self.run_command(["bash", str(script)], env=env)

            self.assertEqual(switched_off.returncode, 3)
            self.assertIn("önjavítás kikapcsolva", switched_off.stderr)
            self.assertTrue((state / "HALTED").exists())

    def test_selfheal_gives_up_after_the_configured_attempt_budget(self) -> None:
        script = ROOT / "tools" / "round-pipeline.sh"
        with tempfile.TemporaryDirectory() as directory_name:
            state = Path(directory_name)
            (state / "HALTED").write_text("round=E09-R01\nhalt=H6\nsummary=teszt halt\n")
            (state / "selfheal.count").write_text("E09-R01|H6|2\n")
            env = dict(os.environ)
            env.update(
                PIPELINE_STATE_DIR=str(state),
                PIPELINE_SELFHEAL_MAX="2",
                PIPELINE_NO_LAUNCH="1",
            )

            exhausted = self.run_command(["bash", str(script)], env=env)

            self.assertEqual(exhausted.returncode, 3)
            self.assertIn("KIMERÜLT", exhausted.stderr)
            # A kimerült keret nem indíthat újabb sessiont, és nem old fel.
            self.assertNotIn("ÖNJAVÍTÓ KÖR indul", exhausted.stderr)
            self.assertTrue((state / "HALTED").exists())

    def test_selfheal_skips_a_round_that_already_has_an_active_heal_session(self) -> None:
        # Measured live 2026-08-16 (E07-R09 H-NOSIGNAL self-heal, attempt
        # 1/3 -- this very session): attempt_selfheal() never registered the
        # round it was healing in .pipeline/inflight, unlike the normal
        # round-dispatch path (`inflight_add "$round" "$brief"` right before
        # `run_orchestrator_session`; see
        # test_round_pipeline_queue_pending_pr_guard.py for the sibling gap
        # this same registry already closed once, on the OTHER side of the
        # halt/resume boundary). HALTED stays present until ONE heal session
        # resolves it, so every 5-minute cron firing in between saw "HALTED
        # still there, a slot is free" and launched ANOTHER concurrent
        # self-heal attempt for the identical (round, halt_code) --
        # `heal-E07-R09-1` (started 02:00:03) and `heal-E07-R09-2` (started
        # 02:05:02) both ran at once (`tmux ls` showed both sessions alive;
        # `.pipeline/selfheal.count` read `E07-R09|H-NOSIGNAL|2` before
        # either had finished), both about to write the SAME shared
        # heal-status file at the end, each consuming one slot of the
        # 3-attempt self-heal budget for a launch race rather than a real
        # failure.
        script = ROOT / "tools" / "round-pipeline.sh"
        with tempfile.TemporaryDirectory() as directory_name:
            state = Path(directory_name)
            (state / "HALTED").write_text("round=E09-R01\nhalt=H-NOSIGNAL\nsummary=teszt halt\n")
            inflight = state / "inflight"
            inflight.mkdir()
            (inflight / "E09-R01").write_text(
                "round=E09-R01\nbrief=heal:H-NOSIGNAL\nbranch=\nworktree=\n"
                "started_at=2026-08-16T02:00:03+00:00\n"
            )
            env = dict(os.environ)
            env.update(
                PIPELINE_STATE_DIR=str(state),
                PIPELINE_NO_LAUNCH="1",
            )

            result = self.run_command(["bash", str(script)], env=env)

            self.assertEqual(result.returncode, 3)
            self.assertIn("már fut", result.stderr)
            # A concurrent-launch skip must not burn the attempt budget --
            # it is not a genuine failed attempt.
            self.assertNotIn("ÖNJAVÍTÓ KÖR indul", result.stderr)
            self.assertFalse((state / "selfheal.count").exists())
            self.assertTrue((state / "HALTED").exists())
            # The pre-existing marker (simulating the other, still-running
            # session) must survive untouched -- this firing must not remove
            # a marker it did not create.
            self.assertTrue((inflight / "E09-R01").exists())

    def test_selfheal_registers_and_clears_its_own_inflight_marker(self) -> None:
        # Companion to the skip test above: the skip test proves the guard
        # RESPECTS a pre-existing marker, but seeds that marker by hand, so
        # it cannot tell a real `inflight_add` call apart from one that was
        # never made. This test proves the OTHER half: attempt_selfheal()
        # itself must call `inflight_add` before launching (so a concurrent
        # firing a moment later would actually see it) and `inflight_remove`
        # once run_orchestrator_session returns (so a failed-to-launch
        # attempt does not leave a permanent "already running" marker
        # behind) -- via a python3 stub that transparently logs matching
        # `round-slots.py inflight-add|inflight-remove` invocations while
        # still executing them for real, so the on-disk marker lifecycle
        # (created, then gone) is exercised exactly as in production.
        script = ROOT / "tools" / "round-pipeline.sh"
        real_python3 = shutil.which("python3")
        self.assertIsNotNone(real_python3, "python3 kell a teszthez")
        with tempfile.TemporaryDirectory() as directory_name:
            state = Path(directory_name)
            stub_bin = state / "bin"
            stub_bin.mkdir()
            call_log = state / "inflight-calls.log"
            stub = stub_bin / "python3"
            stub.write_text(
                "#!/bin/sh\n"
                "case \"$*\" in\n"
                "  *round-slots.py*inflight-add*|*round-slots.py*inflight-remove*)\n"
                f"    echo \"$*\" >> {call_log}\n"
                "    ;;\n"
                "esac\n"
                f"exec {real_python3} \"$@\"\n"
            )
            stub.chmod(0o755)
            (state / "HALTED").write_text("round=E09-R01\nhalt=H-NOSIGNAL\nsummary=teszt halt\n")
            env = dict(os.environ)
            env.update(
                PIPELINE_STATE_DIR=str(state),
                PIPELINE_NO_LAUNCH="1",
                PATH=f"{stub_bin}:{env['PATH']}",
            )

            result = self.run_command(["bash", str(script)], env=env)

            self.assertEqual(result.returncode, 3)
            self.assertIn("ÖNJAVÍTÓ KÖR indul", result.stderr)
            self.assertIn("jelzés nélkül ért véget", result.stderr)
            self.assertEqual((state / "selfheal.count").read_text(), "E09-R01|H-NOSIGNAL|1\n")

            calls = call_log.read_text().splitlines() if call_log.exists() else []
            self.assertTrue(
                any("inflight-add" in line and "--round E09-R01" in line for line in calls),
                f"attempt_selfheal() must register itself before launching; calls={calls!r}",
            )
            self.assertTrue(
                any("inflight-remove" in line and "--round E09-R01" in line for line in calls),
                f"attempt_selfheal() must deregister itself once the launch attempt ends; calls={calls!r}",
            )
            # The marker registered for the (failed-to-launch) attempt must
            # not leak past this firing -- the NEXT firing must be free to
            # retry rather than seeing a permanently-stuck "already running".
            self.assertFalse((state / "inflight" / "E09-R01").exists())

    def test_selfheal_attempt_counter_is_scoped_to_round_and_halt_code(self) -> None:
        script = ROOT / "tools" / "round-pipeline.sh"
        with tempfile.TemporaryDirectory() as directory_name:
            state = Path(directory_name)
            (state / "selfheal.count").write_text("E09-R01|H6|2\n")
            env = dict(os.environ)
            env["PIPELINE_STATE_DIR"] = str(state)

            same = self.run_command(["bash", str(script), "--heal-attempts", "E09-R01", "H6"], env=env)
            other_code = self.run_command(["bash", str(script), "--heal-attempts", "E09-R01", "H5"], env=env)
            other_round = self.run_command(["bash", str(script), "--heal-attempts", "E09-R02", "H6"], env=env)

            self.assertEqual(same.stdout.strip(), "2")
            self.assertEqual(other_code.stdout.strip(), "0")
            self.assertEqual(other_round.stdout.strip(), "0")

    def test_terra_hold_active_test_hook_matches_round_and_future_timestamp(self) -> None:
        # E03-R08 H6 self-heal (2026-08-02): the shared daily Terra budget
        # (.ai/router.toml max_automatic_terra_calls_per_utc_day) only
        # resets at UTC midnight, not on any retry cadence — a hold file
        # scoped to the blocked round should read as active while its
        # deadline is in the future.
        script = ROOT / "tools" / "round-pipeline.sh"
        real_python3 = shutil.which("python3")
        self.assertIsNotNone(real_python3, "python3 kell a teszthez")
        with tempfile.TemporaryDirectory() as directory_name:
            state = Path(directory_name)
            stub_bin = state / "bin"
            stub_bin.mkdir()
            stub = stub_bin / "python3"
            stub.write_text(
                "#!/bin/sh\n"
                "case \"$*\" in\n"
                "  *model-router.py*terra-status*)\n"
                "    printf '{\"unlimited\": false, \"exhausted\": false}'\n"
                "    exit 0\n"
                "    ;;\n"
                "  *)\n"
                f"    exec {real_python3} \"$@\"\n"
                "    ;;\n"
                "esac\n"
            )
            stub.chmod(0o755)
            future = int(time.time()) + 3600
            (state / "terra-budget-hold").write_text(f"round=E03-R08\nhold_until={future}\n")
            env = dict(os.environ)
            env["PIPELINE_STATE_DIR"] = str(state)
            env["PATH"] = f"{stub_bin}:{env['PATH']}"

            active = self.run_command(["bash", str(script), "--terra-hold-active", "E03-R08"], env=env)
            other_round = self.run_command(["bash", str(script), "--terra-hold-active", "E03-R09"], env=env)

            self.assertEqual(active.returncode, 0, active.stderr)
            self.assertIn("felfüggesztés aktív", active.stderr)
            self.assertEqual(other_round.returncode, 1, other_round.stderr)

    def test_unlimited_terra_policy_removes_a_stale_daily_budget_hold(self) -> None:
        script = ROOT / "tools" / "round-pipeline.sh"
        real_python3 = shutil.which("python3")
        self.assertIsNotNone(real_python3, "python3 kell a teszthez")
        with tempfile.TemporaryDirectory() as directory_name:
            state = Path(directory_name)
            stub_bin = state / "bin"
            stub_bin.mkdir()
            stub = stub_bin / "python3"
            stub.write_text(
                "#!/bin/sh\n"
                "case \"$*\" in\n"
                "  *model-router.py*terra-status*)\n"
                "    printf '{\"unlimited\": true, \"exhausted\": false}'\n"
                "    exit 0\n"
                "    ;;\n"
                "  *)\n"
                f"    exec {real_python3} \"$@\"\n"
                "    ;;\n"
                "esac\n"
            )
            stub.chmod(0o755)
            hold_file = state / "terra-budget-hold"
            hold_file.write_text(
                f"round=E03-R08\nhold_until={int(time.time()) + 3600}\n"
            )
            env = dict(os.environ)
            env["PIPELINE_STATE_DIR"] = str(state)
            env["PATH"] = f"{stub_bin}:{env['PATH']}"

            result = self.run_command(
                ["bash", str(script), "--terra-hold-active", "E03-R08"], env=env
            )

            self.assertEqual(result.returncode, 1, result.stderr)
            self.assertFalse(hold_file.exists())

    def test_stale_h6_halt_is_cleared_once_the_daily_terra_cap_goes_unlimited(self) -> None:
        # MÉRT gyökérok (E03-R08 H6, 7. előfordulás, 2026-08-02 18:45 UTC,
        # heal-prompt-E03-R08-20260802T184502.md): a napi Terra-korlát
        # eltávolítása (PR #72, `max_automatic_terra_calls_per_utc_day = 0`
        # = unlimited) után az ELSŐ firing helyesen törölte az akkor még élő
        # `terra-budget-hold` fájlt (l.
        # `test_unlimited_terra_policy_removes_a_stale_daily_budget_hold`
        # fentebb) — attól kezdve a hold-fájl NEM LÉTEZIK többé. A
        # `.pipeline/HALTED` fájl viszont, amit a MÉG korlátozott policy
        # alatt írt ki `handle_round_halt` ugyanerre a Terra-kimerülésre,
        # érintetlen maradt, és a driver főági 2. szakasza (`[ -f
        # "$halt_file" ]`) ezt — a hold-fájl (nemlétező) állapotától
        # TELJESEN függetlenül — egy ÚJABB, valódi önjavító sessionnek nézte.
        # Élesben ez pontosan megtörtént (heal-E03-R08-20260802T184502.log,
        # 7. heal-session egy már megszűnt okra). Ez a teszt EZT a valós
        # állapotot reprodukálja: NINCS hold-fájl, csak a stale HALTED —
        # `terra_clear_stale_halt_for` önállóan, a hold-fájl létezésétől
        # függetlenül kell hogy lekérdezze a policy-t és archiválja a
        # HALTED-et.
        #
        # SAFETY (mérve, ennek a tesztnek egy korábbi verziója élesen
        # megtörtént: egy RED futás — a `--terra-clear-stale-halt` hook még
        # nem létezett — a flag-et ismeretlen argumentumként átengedte a
        # TELJES driver-folyamatnak, ami a HALTED-re egy VALÓDI
        # tmux+claude önjavító sessiont indított ezen a repón, kézzel kellett
        # leállítani). `selfheal.count` ezért a kísérletbüdzsé HATÁRÁN
        # (3) ül, `PIPELINE_SELFHEAL_MAX=3`-mal együtt — pontosan úgy, mint a
        # `test_terra_budget_hold_blocks_a_firing_without_spending_a_selfheal_attempt`
        # mintája: ha a hook hiányzik, a driver a kimerült-büdzsé
        # rövidzárba fut ("KIMERÜLT", session nélkül), sosem spawnol
        # valódi sessiont.
        script = ROOT / "tools" / "round-pipeline.sh"
        real_python3 = shutil.which("python3")
        self.assertIsNotNone(real_python3, "python3 kell a teszthez")
        with tempfile.TemporaryDirectory() as directory_name:
            state = Path(directory_name)
            stub_bin = state / "bin"
            stub_bin.mkdir()
            stub = stub_bin / "python3"
            stub.write_text(
                "#!/bin/sh\n"
                "case \"$*\" in\n"
                "  *model-router.py*terra-status*)\n"
                "    printf '{\"unlimited\": true, \"exhausted\": false}'\n"
                "    exit 0\n"
                "    ;;\n"
                "  *)\n"
                f"    exec {real_python3} \"$@\"\n"
                "    ;;\n"
                "esac\n"
            )
            stub.chmod(0o755)
            halt_file = state / "HALTED"
            halt_file.write_text(
                "round=E03-R08\n"
                "halt=H6\n"
                "summary=auto router task E03-R08 is DEFERRED — Terra's automatic "
                "daily budget is genuinely exhausted for utc_day=2026-08-02\n"
                "halted_at=2026-08-02T16:58:03+00:00\n"
            )
            (state / "selfheal.count").write_text("E03-R08|H6|3\n")
            env = dict(os.environ)
            env["PIPELINE_STATE_DIR"] = str(state)
            env["PIPELINE_SELFHEAL_MAX"] = "3"
            env["PATH"] = f"{stub_bin}:{env['PATH']}"

            result = self.run_command(
                ["bash", str(script), "--terra-clear-stale-halt", "E03-R08"], env=env
            )

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertFalse(
                halt_file.exists(),
                "a stale H6 HALTED fájlnak el kell tűnnie, amikor a napi Terra-korlát "
                "megszűnik — különben a következő firing felesleges önjavítást indít",
            )
            self.assertFalse(
                (state / "selfheal.count").exists(),
                "a kísérletszámlálónak nullázódnia kell, mert ez nem egy valódi javítás volt",
            )
            healed = list(state.glob("healed-E03-R08-*.txt"))
            self.assertEqual(len(healed), 1, "a stale halt-ot archiválni kell, nem eldobni")
            self.assertIn("Terra", healed[0].read_text())

    def test_stale_h6_halt_survives_when_daily_terra_cap_is_still_finite(self) -> None:
        # A biztonsági ellenpélda: amíg a napi Terra-korlát ténylegesen
        # kimerült (nem `unlimited`), a HALTED-nek ÉLNIE kell — ez a
        # naptár-korlátozott, valódi halt, amit [[L62]]/[[L65]] szándékosan
        # nem old fel session/heal-kísérlet nélkül.
        #
        # SAFETY: ugyanaz az indoklás, mint a fenti
        # `test_stale_h6_halt_is_cleared_once_the_daily_terra_cap_goes_unlimited`-ben
        # — `selfheal.count` a büdzsé HATÁRÁN ül, hogy egy hiányzó hook
        # esetén a driver sose spawnoljon valódi tmux+claude sessiont.
        script = ROOT / "tools" / "round-pipeline.sh"
        real_python3 = shutil.which("python3")
        self.assertIsNotNone(real_python3, "python3 kell a teszthez")
        with tempfile.TemporaryDirectory() as directory_name:
            state = Path(directory_name)
            stub_bin = state / "bin"
            stub_bin.mkdir()
            stub = stub_bin / "python3"
            stub.write_text(
                "#!/bin/sh\n"
                "case \"$*\" in\n"
                "  *model-router.py*terra-status*)\n"
                "    printf '{\"unlimited\": false, \"exhausted\": true}'\n"
                "    exit 1\n"
                "    ;;\n"
                "  *)\n"
                f"    exec {real_python3} \"$@\"\n"
                "    ;;\n"
                "esac\n"
            )
            stub.chmod(0o755)
            halt_file = state / "HALTED"
            halt_file.write_text(
                "round=E03-R08\n"
                "halt=H6\n"
                "summary=auto router task E03-R08 is DEFERRED — Terra's automatic "
                "daily budget is genuinely exhausted for utc_day=2026-08-02\n"
                "halted_at=2026-08-02T16:58:03+00:00\n"
            )
            (state / "selfheal.count").write_text("E03-R08|H6|3\n")
            env = dict(os.environ)
            env["PIPELINE_STATE_DIR"] = str(state)
            env["PIPELINE_SELFHEAL_MAX"] = "3"
            env["PATH"] = f"{stub_bin}:{env['PATH']}"

            result = self.run_command(
                ["bash", str(script), "--terra-clear-stale-halt", "E03-R08"], env=env
            )

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertTrue(
                halt_file.exists(),
                "amíg a napi Terra-korlát ténylegesen kimerült, a HALTED-et nem "
                "szabad törölni",
            )

    def test_unlimited_terra_policy_keeps_hold_active_when_removal_fails(self) -> None:
        script = ROOT / "tools" / "round-pipeline.sh"
        real_python3 = shutil.which("python3")
        self.assertIsNotNone(real_python3, "python3 kell a teszthez")
        with tempfile.TemporaryDirectory() as directory_name:
            state = Path(directory_name)
            stub_bin = state / "bin"
            stub_bin.mkdir()
            python_stub = stub_bin / "python3"
            python_stub.write_text(
                "#!/bin/sh\n"
                "case \"$*\" in\n"
                "  *model-router.py*terra-status*)\n"
                "    printf '{\"unlimited\": true, \"exhausted\": false}'\n"
                "    exit 0\n"
                "    ;;\n"
                "  *)\n"
                f"    exec {real_python3} \"$@\"\n"
                "    ;;\n"
                "esac\n"
            )
            python_stub.chmod(0o755)
            rm_stub = stub_bin / "rm"
            rm_stub.write_text("#!/bin/sh\nexit 1\n")
            rm_stub.chmod(0o755)
            hold_file = state / "terra-budget-hold"
            hold_file.write_text(
                f"round=E03-R08\nhold_until={int(time.time()) + 3600}\n"
            )
            env = dict(os.environ)
            env["PIPELINE_STATE_DIR"] = str(state)
            env["PATH"] = f"{stub_bin}:{env['PATH']}"

            result = self.run_command(
                ["bash", str(script), "--terra-hold-active", "E03-R08"], env=env
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("elavult Terra-hold nem törölhető", result.stderr)
            self.assertTrue(hold_file.exists())

    def test_terra_hold_remains_fail_closed_when_policy_status_is_unavailable(self) -> None:
        script = ROOT / "tools" / "round-pipeline.sh"
        real_python3 = shutil.which("python3")
        self.assertIsNotNone(real_python3, "python3 kell a teszthez")
        with tempfile.TemporaryDirectory() as directory_name:
            state = Path(directory_name)
            stub_bin = state / "bin"
            stub_bin.mkdir()
            stub = stub_bin / "python3"
            stub.write_text(
                "#!/bin/sh\n"
                "case \"$*\" in\n"
                "  *model-router.py*terra-status*) exit 50 ;;\n"
                "  *)\n"
                f"    exec {real_python3} \"$@\"\n"
                "    ;;\n"
                "esac\n"
            )
            stub.chmod(0o755)
            hold_file = state / "terra-budget-hold"
            hold_file.write_text(
                f"round=E03-R08\nhold_until={int(time.time()) + 3600}\n"
            )
            env = dict(os.environ)
            env["PIPELINE_STATE_DIR"] = str(state)
            env["PATH"] = f"{stub_bin}:{env['PATH']}"

            result = self.run_command(
                ["bash", str(script), "--terra-hold-active", "E03-R08"], env=env
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(hold_file.exists())

    def test_terra_hold_expired_deadline_is_inactive_and_self_clears(self) -> None:
        script = ROOT / "tools" / "round-pipeline.sh"
        with tempfile.TemporaryDirectory() as directory_name:
            state = Path(directory_name)
            past = int(time.time()) - 60
            hold_file = state / "terra-budget-hold"
            hold_file.write_text(f"round=E03-R08\nhold_until={past}\n")
            env = dict(os.environ)
            env["PIPELINE_STATE_DIR"] = str(state)

            expired = self.run_command(["bash", str(script), "--terra-hold-active", "E03-R08"], env=env)

            self.assertEqual(expired.returncode, 1, expired.stderr)
            self.assertFalse(hold_file.exists())

    def test_terra_budget_hold_blocks_a_firing_without_spending_a_selfheal_attempt(self) -> None:
        # The end-to-end regression: a HALT on the round the hold names must
        # make the WHOLE driver invocation a cheap no-op (no selfheal
        # session, no attempt-counter burn) while the hold is in the future
        # — this is what stops the retry loop from exhausting the 3-attempt
        # self-heal budget minutes into an 8+ hour calendar-gated wait.
        #
        # SAFETY (measured the hard way, E03-R08 H6 2nd heal, 2026-08-02):
        # selfheal.count is seeded AT the attempt budget (3), matching the
        # already-safe `test_selfheal_gives_up_after_the_configured_attempt_budget`
        # pattern above — NOT one below it. Without this driver's hold gate
        # (e.g. reverted for a RED check), a below-budget counter lets
        # `attempt_selfheal()` run for real and spawn an ACTUAL tmux+claude
        # self-heal session with --permission-mode bypassPermissions against
        # this real repo (confirmed: it happened, branch heal/E03-R08-H6-3,
        # had to be killed by hand). At-budget keeps every code path —
        # pre-fix AND post-fix — inside the exhausted-budget short-circuit,
        # which spawns nothing; only the exit code/message differ (0 + "hold
        # active" post-fix vs. 3 + "KIMERÜLT" pre-fix), which is enough to
        # tell the fix apart without ever risking a live session.
        script = ROOT / "tools" / "round-pipeline.sh"
        real_python3 = shutil.which("python3")
        self.assertIsNotNone(real_python3, "python3 kell a teszthez")
        with tempfile.TemporaryDirectory() as directory_name:
            state = Path(directory_name)
            stub_bin = state / "bin"
            stub_bin.mkdir()
            stub = stub_bin / "python3"
            stub.write_text(
                "#!/bin/sh\n"
                "case \"$*\" in\n"
                "  *model-router.py*terra-status*)\n"
                "    printf '{\"unlimited\": false, \"exhausted\": true}'\n"
                "    exit 1\n"
                "    ;;\n"
                "  *)\n"
                f"    exec {real_python3} \"$@\"\n"
                "    ;;\n"
                "esac\n"
            )
            stub.chmod(0o755)
            (state / "HALTED").write_text(
                "round=E03-R08\nhalt=H6\nsummary=auto-router DEFERRED: Terra daily budget is exhausted\n"
            )
            future = int(time.time()) + 3600
            (state / "terra-budget-hold").write_text(f"round=E03-R08\nhold_until={future}\n")
            (state / "selfheal.count").write_text("E03-R08|H6|3\n")
            env = dict(os.environ)
            env.update(
                PIPELINE_STATE_DIR=str(state),
                PIPELINE_SELFHEAL_MAX="3",
                PATH=f"{stub_bin}:{env['PATH']}",
                # MÉRVE 2026-08-05: e teszt a stale halt archiválása UTÁN
                # továbbfut a kör-indítási ágra, ahol a VALÓDI queue-t olvassa
                # — tiszta `main`-ről futtatva éles sessiont indított.
                PIPELINE_NO_LAUNCH="1",
            )

            held = self.run_command(["bash", str(script)], env=env)

            self.assertEqual(held.returncode, 0, held.stderr)
            self.assertIn("felfüggesztés aktív", held.stderr)
            self.assertNotIn("ÖNJAVÍTÓ KÖR indul", held.stderr)
            self.assertNotIn("KIMERÜLT", held.stderr)
            self.assertEqual((state / "selfheal.count").read_text(), "E03-R08|H6|3\n")
            self.assertTrue((state / "HALTED").exists())

    def test_a_full_firing_retries_the_round_instead_of_healing_a_resolved_terra_wall(self) -> None:
        # The end-to-end regression for the ACTUAL production incident
        # (E03-R08 H6, 7th occurrence, 2026-08-02 18:45 UTC): by the time
        # this firing runs, an EARLIER firing already cleared the
        # `terra-budget-hold` (the daily cap just went unlimited, PR #72) —
        # so, unlike `test_terra_budget_hold_blocks_a_firing_without_spending_a_selfheal_attempt`
        # above, there is NO hold file left. Only the stale `.pipeline/HALTED`
        # (written while the cap was still finite) remains. Pre-fix, the
        # driver's HALT branch doesn't re-check the condition and launches a
        # brand new self-heal session for a wall that no longer exists.
        #
        # SAFETY (same reasoning as the sibling test above): selfheal.count
        # is seeded AT the attempt budget (3), so IF the fix regresses and
        # the old code path is taken, `attempt_selfheal()` hits the
        # exhausted-budget short-circuit (logs "KIMERÜLT", returns 3) instead
        # of spawning a real tmux+claude session — this keeps a RED run of
        # this test safe to execute against this real repo.
        script = ROOT / "tools" / "round-pipeline.sh"
        real_python3 = shutil.which("python3")
        self.assertIsNotNone(real_python3, "python3 kell a teszthez")
        with tempfile.TemporaryDirectory() as directory_name:
            state = Path(directory_name)
            stub_bin = state / "bin"
            stub_bin.mkdir()
            stub = stub_bin / "python3"
            stub.write_text(
                "#!/bin/sh\n"
                "case \"$*\" in\n"
                "  *model-router.py*terra-status*)\n"
                "    printf '{\"unlimited\": true, \"exhausted\": false}'\n"
                "    exit 0\n"
                "    ;;\n"
                "  *)\n"
                f"    exec {real_python3} \"$@\"\n"
                "    ;;\n"
                "esac\n"
            )
            stub.chmod(0o755)
            (state / "HALTED").write_text(
                "round=E03-R08\nhalt=H6\nsummary=auto-router DEFERRED: Terra's automatic "
                "daily budget is genuinely exhausted for utc_day=2026-08-02\n"
            )
            (state / "selfheal.count").write_text("E03-R08|H6|3\n")
            env = dict(os.environ)
            env.update(
                PIPELINE_STATE_DIR=str(state),
                PIPELINE_SELFHEAL_MAX="3",
                PATH=f"{stub_bin}:{env['PATH']}",
                # MÉRVE 2026-08-05: e teszt a stale halt archiválása UTÁN
                # továbbfut a kör-indítási ágra, ahol a VALÓDI queue-t olvassa
                # — tiszta `main`-ről futtatva éles sessiont indított.
                PIPELINE_NO_LAUNCH="1",
                # MÉRVE 2026-08-19 (pytest a boxon, tiszta `main`): a
                # `PIPELINE_NO_LAUNCH` csak a SESSIONT hagyja el, a kör-ág
                # kiválasztását nem — a driver lefut a dispatchig, a session
                # jelzés nélkül "ér véget", és `handle_round_halt` ÚJ HALTED-et
                # ír. Az alábbi `assertFalse(HALTED)` cella így nem a stale halt
                # archiválását mérte, hanem azt, hogy a firing a dispatch ELŐTT
                # elhal (CI-ban: a checkout nem `main`-en van → teszt-módú
                # `die`) — környezetfüggő zöld, nem mérés. Izolált, kizárólag
                # 'done' sorokból álló sorral a mért viselkedés (stale halt
                # archiválva, önjavítás nem indul) változatlan, a zaj eltűnik.
                PIPELINE_QUEUE_FILE=str(state / "empty-queue.tsv"),
            )

            (state / "empty-queue.tsv").write_text(
                "# minden sor 'done' — ennek a firingnek nincs mit dispatchelnie\n"
                "E03-R08\tdocs/rounds/e03-r08-persistent-v2-migration.md\tcodex\tnincs\tdone\n",
                encoding="utf-8",
            )

            result = self.run_command(["bash", str(script)], env=env)

            self.assertNotIn("ÖNJAVÍTÓ KÖR indul", result.stderr)
            self.assertNotIn("KIMERÜLT", result.stderr)
            self.assertIn("HALTED jelzés elavult volt", result.stderr)
            self.assertFalse((state / "HALTED").exists())
            self.assertFalse((state / "selfheal.count").exists())
            self.assertEqual(
                len(list(state.glob("healed-E03-R08-*.txt"))),
                1,
                "a stale halt-ot archiválni kell, nem eldobni",
            )

    def test_terra_hold_if_exhausted_writes_the_hold_file_when_terra_status_reports_exhausted(self) -> None:
        # MÉRT gyökérok (E03-R08 H6, 2. önjavítás, 2026-08-02, ugyanaz a halt
        # 4x egy nap alatt): `terra_hold_if_exhausted()`-ben a
        # `status_json=$(terra_status_json) || return 0` BÁRMILYEN nemnulla
        # exit-re kilépett — de a `model-router.py terra-status` a
        # DOKUMENTÁLT viselkedése szerint (HANDOFF.md) pontosan akkor tér
        # vissza nemnulla exit-tel, amikor exhausted=true. Emiatt a hold-fájl
        # SOHA nem íródott ki, holott három korábbi heal-session is azt
        # hitte (a saját szövegében), hogy a hold aktiválódik. Ez a teszt a
        # tényleges ÍRÓ függvényt (`terra_hold_if_exhausted`) hívja végig egy
        # PATH-stub `python3`-mal, ami a `terra-status` valódi mért
        # viselkedését szimulálja (exhausted JSON, exit 1) — a korábbi
        # `test_terra_hold_active_test_hook_matches_round_and_future_timestamp`
        # csak az OLVASÓ függvényt (`terra_hold_active_for`) tesztelte, kézzel
        # megírt hold-fájllal, ezért nem fogta meg ezt a hibát.
        script = ROOT / "tools" / "round-pipeline.sh"
        real_python3 = shutil.which("python3")
        self.assertIsNotNone(real_python3, "python3 kell a teszthez")
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            stub_bin = directory / "bin"
            stub_bin.mkdir()
            next_epoch = int(time.time()) + 3600
            stub = stub_bin / "python3"
            stub.write_text(
                "#!/bin/sh\n"
                "case \"$*\" in\n"
                "  *model-router.py*terra-status*)\n"
                f"    printf '{{\"exhausted\": true, \"next_reset_epoch\": {next_epoch}}}'\n"
                "    exit 1\n"
                "    ;;\n"
                "  *)\n"
                f"    exec {real_python3} \"$@\"\n"
                "    ;;\n"
                "esac\n"
            )
            stub.chmod(0o755)
            env = dict(os.environ)
            env["PIPELINE_STATE_DIR"] = str(directory)
            env["PATH"] = f"{stub_bin}:{env['PATH']}"

            result = self.run_command(
                ["bash", str(script), "--terra-hold-if-exhausted", "E03-R08"], env=env
            )

            hold_file = directory / "terra-budget-hold"
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertTrue(
                hold_file.exists(),
                "terra_hold_if_exhausted nem írta ki a hold-fájlt kimerült Terra-budget mellett",
            )
            content = hold_file.read_text()
            self.assertIn("round=E03-R08", content)
            self.assertIn(f"hold_until={next_epoch}", content)

    def test_terra_hold_writer_is_a_no_op_under_unlimited_policy(self) -> None:
        script = ROOT / "tools" / "round-pipeline.sh"
        real_python3 = shutil.which("python3")
        self.assertIsNotNone(real_python3, "python3 kell a teszthez")
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            stub_bin = directory / "bin"
            stub_bin.mkdir()
            next_epoch = int(time.time()) + 3600
            stub = stub_bin / "python3"
            stub.write_text(
                "#!/bin/sh\n"
                "case \"$*\" in\n"
                "  *model-router.py*terra-status*)\n"
                "    printf '{\"unlimited\": true, \"exhausted\": false, "
                f"\"next_reset_epoch\": {next_epoch}}}'\n"
                "    exit 0\n"
                "    ;;\n"
                "  *)\n"
                f"    exec {real_python3} \"$@\"\n"
                "    ;;\n"
                "esac\n"
            )
            stub.chmod(0o755)
            env = dict(os.environ)
            env["PIPELINE_STATE_DIR"] = str(directory)
            env["PATH"] = f"{stub_bin}:{env['PATH']}"

            result = self.run_command(
                ["bash", str(script), "--terra-hold-if-exhausted", "E03-R08"], env=env
            )

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertFalse((directory / "terra-budget-hold").exists())

    def test_first_halt_detection_writes_the_terra_hold_without_waiting_for_a_selfheal_retry(self) -> None:
        # MÉRT gyökérok (E03-R08 H6, 6. halt ugyanazon a napon, 2026-08-02
        # 14:26-16:38 UTC): a Terra napi-hold korábban KIZÁRÓLAG
        # attempt_selfheal() retry-ágából íródott ki, az önjavító session
        # LLM-jelentésének SZÖVEGÉRE string-matchelve (`*"Terra"*"budget"*`).
        # A 16:20-16:30-as heal-kör egy MÁSIK gyökérokot javított (magát a
        # hold-író `terra_hold_if_exhausted()` függvényt, PR #70) —
        # `outcome=fixed`, nem `retry` — így ez az ág NEM futott le, a
        # hold-fájl nem íródott ki, és a 16:35-ös következő firing UGYANAZT
        # a naptár-korlátozott Terra-falat érte el újra (6. halt 16:38-kor).
        # Ez a teszt a HALT ELSŐ észlelésének útvonalát (`handle_round_halt`,
        # a `round-status`-ban `outcome=halted`-öt jelentő ELSŐ futás) hívja
        # végig egy kimerült Terra-státuszt szimuláló python3-stubbal —
        # a holdnak MÁR ekkor, bármilyen self-heal session előtt ki kell
        # íródnia, nem várhat egy retry-klasszifikációra.
        script = ROOT / "tools" / "round-pipeline.sh"
        real_python3 = shutil.which("python3")
        self.assertIsNotNone(real_python3, "python3 kell a teszthez")
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            stub_bin = directory / "bin"
            stub_bin.mkdir()
            next_epoch = int(time.time()) + 3600
            stub = stub_bin / "python3"
            stub.write_text(
                "#!/bin/sh\n"
                "case \"$*\" in\n"
                "  *model-router.py*terra-status*)\n"
                f"    printf '{{\"exhausted\": true, \"next_reset_epoch\": {next_epoch}}}'\n"
                "    exit 1\n"
                "    ;;\n"
                "  *)\n"
                f"    exec {real_python3} \"$@\"\n"
                "    ;;\n"
                "esac\n"
            )
            stub.chmod(0o755)
            status_file = directory / "round-status"
            status_file.write_text(
                "outcome=halted\n"
                "halt=H6\n"
                "summary=auto router task still DEFERRED (mandatory Terra high-risk review) "
                "— Terra's daily budget is genuinely exhausted for utc_day=2026-08-02\n"
            )
            session_log = directory / "session-E03-R08-test.log"
            session_log.write_text("")
            env = dict(os.environ)
            env["PIPELINE_STATE_DIR"] = str(directory)
            env["PATH"] = f"{stub_bin}:{env['PATH']}"

            result = self.run_command(
                [
                    "bash",
                    str(script),
                    "--handle-round-halt",
                    "E03-R08",
                    str(status_file),
                    str(session_log),
                ],
                env=env,
            )

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertTrue((directory / "HALTED").exists())
            hold_file = directory / "terra-budget-hold"
            self.assertTrue(
                hold_file.exists(),
                "a HALT első észlelése nem írta ki a Terra-holdot — a következő firing "
                "önjavítási kísérlet elköltése nélkül újra nekifutna ugyanennek a falnak",
            )
            content = hold_file.read_text()
            self.assertIn("round=E03-R08", content)
            self.assertIn(f"hold_until={next_epoch}", content)

    def test_gate_fingerprint_covers_the_test_count_and_the_gate_artifacts(self) -> None:
        script = ROOT / "tools" / "round-pipeline.sh"
        fingerprint = self.run_command(["bash", str(script), "--gate-fingerprint"])

        self.assertEqual(fingerprint.returncode, 0, fingerprint.stderr)
        count = int(fingerprint.stdout.split("tests=", 1)[1].split()[0])
        self.assertGreater(count, 100)
        for artifact in (
            "tools/round-gate.sh",
            ".github/workflows/build-apk.yml",
            ".github/workflows/router-ci.yml",
        ):
            self.assertIn(f"{artifact}:", fingerprint.stdout)
            self.assertNotIn(f"{artifact}:hiányzik", fingerprint.stdout)

    def make_fake_gh(self, directory: Path) -> Path:
        # A H-GATEGUARD-teszteknek NEM szabad élő hálózati `gh`-hívástól
        # függenie (a router-ci.yml futtatója nincs `gh auth`-olva) — ezért egy
        # PATH-on elé tolt stubot adunk, ami a valós `gh pr list`/`gh pr view`
        # helyett a FAKE_GH_* env-változókat visszhangozza. A git-diffek maguk
        # a VALÓDI repó VALÓDI, már merge-elt commitjain futnak (lásd lent).
        fake_gh = directory / "gh"
        fake_gh.write_text(
            "#!/usr/bin/env bash\n"
            "case \"$1 $2\" in\n"
            "  \"pr list\") printf '%s\\n' \"${FAKE_GH_PR_NUMBER:-}\" ;;\n"
            "  \"pr view\") printf '%s\\n' \"${FAKE_GH_MERGE_SHA:-}\" ;;\n"
            "  *) echo \"fake-gh: unsupported invocation: $*\" >&2; exit 1 ;;\n"
            "esac\n"
        )
        fake_gh.chmod(0o755)
        return directory

    def test_heal_pr_number_resolves_the_deterministic_heal_branch_via_gh_pr_list(self) -> None:
        # A heal branch neve determinisztikus (heal/{ROUND}-{HALT_CODE}-
        # {ATTEMPT}, docs/execution/pipeline-selfheal-prompt.md) -- ez a
        # H-GATEGUARD hamis-pozitívjának javítási alapja (lásd lent). A `gh`
        # hívást stuboljuk: a router-ci.yml futtatója nincs `gh auth`-olva,
        # élő hálózati hívástól a teszt nem függhet (mérve: e nélkül a
        # stub nélkül ez a teszt CI-ban `gh`-hiba miatt üresen bukik, nem a
        # függvény logikáján). Manuálisan, éles `gh`-val ELLENŐRIZVE (docs/
        # LESSONS.md L55): `heal/E03-R05-H6-1` valóban a #61 PR-re old fel.
        script = ROOT / "tools" / "round-pipeline.sh"
        with tempfile.TemporaryDirectory() as directory_name:
            bin_dir = self.make_fake_gh(Path(directory_name))
            env = dict(os.environ, PATH=f"{bin_dir}:{os.environ['PATH']}")

            env["FAKE_GH_PR_NUMBER"] = "61"
            found = self.run_command(
                ["bash", str(script), "--heal-pr-number", "heal/E03-R05-H6-1"], env=env
            )
            self.assertEqual(found.stdout.strip(), "61", found.stdout + found.stderr)

            env["FAKE_GH_PR_NUMBER"] = ""
            missing = self.run_command(
                ["bash", str(script), "--heal-pr-number", "heal/does-not-exist-1"], env=env
            )
            self.assertEqual(missing.stdout.strip(), "", missing.stdout + missing.stderr)

    def make_gate_guard_fixture_commit(self, updates: dict[str, str]) -> str:
        # heal_pr_gate_violation() a `merge_sha^..merge_sha`-t EBBEN a
        # checkout-ban diffeli (repo_root a szkript saját helyére van
        # kötve) -- egy külön, ideiglenes git repó tehát nem adna neki
        # feldolgozható SHA-kat. Ehelyett egy VALÓDI, feloldható commit
        # OBJEKTUMOT építünk a checkout jelenlegi valódi HEAD-je fölé
        # plumbing-parancsokkal, egy privát GIT_INDEX_FILE-on át (a valódi
        # indexet/munkafát és minden ref/branch-et érintetlenül hagyva) --
        # ez CI shallow (fetch-depth=1) klónjában is működik, mert csak a
        # HEAD-re van szüksége, nem tetszőleges régi történelemre (a
        # `6d61e23`/`3b4707f` mért, valódi commitokra hivatkozó korábbi
        # verzió pont ezért bukott CI-ban: a shallow klón nem tartalmazta
        # őket — docs/LESSONS.md L55).
        with tempfile.TemporaryDirectory() as scratch_dir:
            index_file = Path(scratch_dir) / "index"
            env = dict(os.environ, GIT_INDEX_FILE=str(index_file))
            subprocess.run(
                ["git", "read-tree", "HEAD"], cwd=ROOT, env=env, check=True, capture_output=True
            )
            for path, content in updates.items():
                blob = subprocess.run(
                    ["git", "hash-object", "-w", "--stdin"],
                    cwd=ROOT, env=env, input=content, text=True, capture_output=True, check=True,
                ).stdout.strip()
                subprocess.run(
                    ["git", "update-index", "--add", "--cacheinfo", f"100644,{blob},{path}"],
                    cwd=ROOT, env=env, check=True, capture_output=True,
                )
            tree = subprocess.run(
                ["git", "write-tree"], cwd=ROOT, env=env, check=True, capture_output=True, text=True,
            ).stdout.strip()
            # `commit-tree` needs an author/committer identity; a fresh CI
            # runner has no `user.name`/`user.email` configured (mérve: ez a
            # 2. CI-only bukás, exit 128 "empty ident" a router-ci.yml
            # runneren), ezért explicit GIT_*_NAME/EMAIL-t adunk, nem a
            # környezet globális git configjára támaszkodva.
            commit_env = dict(
                os.environ,
                GIT_AUTHOR_NAME="gate-guard-test",
                GIT_AUTHOR_EMAIL="gate-guard-test@example.invalid",
                GIT_COMMITTER_NAME="gate-guard-test",
                GIT_COMMITTER_EMAIL="gate-guard-test@example.invalid",
            )
            commit = subprocess.run(
                ["git", "commit-tree", tree, "-p", "HEAD", "-m", "gate-guard test fixture (not a real round)"],
                cwd=ROOT, env=commit_env, check=True, capture_output=True, text=True,
            ).stdout.strip()
            return commit

    def test_heal_pr_gate_violation_ignores_a_clean_diff_and_catches_a_gate_touch(self) -> None:
        # RED-ELŐZMÉNY (E03-R05, a H6 heal UTÁNI H-GATEGUARD halt, mérve
        # 2026-08-02): a régi őrszem a teljes main előtte/utána ujjlenyomatát
        # hasonlította össze, ezért hamisan gyanúsította a H6 heal saját,
        # tiszta PR-jét (#61 -- valójában csak az orchestrátor-promptot, egy
        # tesztet és egy ÚJ segédscriptet módosított), mert a heal FUTÁSA
        # KÖZBEN egy tőle FÜGGETLEN, jogos commit (8715773, ADR 0115)
        # módosította a router-ci.yml-t. docs/LESSONS.md L55.
        #
        # Az új őrszem a heal SAJÁT PR-diffjét (merge_sha^..merge_sha) nézi,
        # ezért immunis erre. Két szintetikus, de a valós PR-alakot tükröző
        # fixture-commitot építünk a checkout valódi HEAD-je fölé (lásd
        # make_gate_guard_fixture_commit): az egyik csak egy saját, ártalmatlan
        # fájlt érint (mint a heal saját, tiszta PR-je), a másik a VALÓDI
        # tools/round-gate.sh-t módosítja (mint egy tényleg mércét gyengítő
        # diff).
        script = ROOT / "tools" / "round-pipeline.sh"
        clean_sha = self.make_gate_guard_fixture_commit(
            {"tools/tests/__gate_guard_fixture_clean__.md": "gate-guard test fixture: a clean heal PR\n"}
        )
        real_round_gate = (ROOT / "tools" / "round-gate.sh").read_text()
        violation_sha = self.make_gate_guard_fixture_commit(
            {"tools/round-gate.sh": real_round_gate + "\n# gate-guard test fixture touch\n"}
        )

        with tempfile.TemporaryDirectory() as directory_name:
            bin_dir = self.make_fake_gh(Path(directory_name))
            env = dict(os.environ, PATH=f"{bin_dir}:{os.environ['PATH']}")

            env["FAKE_GH_MERGE_SHA"] = clean_sha
            clean = self.run_command(["bash", str(script), "--heal-pr-gate-violation", "999"], env=env)
            self.assertEqual(clean.returncode, 1, clean.stdout + clean.stderr)

            env["FAKE_GH_MERGE_SHA"] = violation_sha
            caught = self.run_command(["bash", str(script), "--heal-pr-gate-violation", "999"], env=env)
            self.assertEqual(caught.returncode, 0, caught.stdout + caught.stderr)
            self.assertIn("round-gate.sh", caught.stdout)

    def test_orchestrator_falls_back_to_terra_only_while_claude_is_blocked(self) -> None:
        # A kvóta-fallback gépezetét (ADR 0115) az `alternate` rotáció alatt
        # mérjük — a 2026-08-20-i Sol-pin default (lásd a lenti
        # `test_the_default_orchestrator_is_the_sol_pin`) a zárlat-mérés
        # ELŐTT dönt, így alatta ez az út nem is fut.
        script = ROOT / "tools" / "round-pipeline.sh"
        with tempfile.TemporaryDirectory() as directory_name:
            state = Path(directory_name)
            env = dict(os.environ)
            env["PIPELINE_STATE_DIR"] = str(state)
            env["PIPELINE_ORCH_ROTATION"] = "alternate"
            # A commitolt rotáció-fájl (P1-fix, 2026-08-20) erősebb az
            # env-nél — az env-szemantika méréséhez üresre irányítjuk.
            env["PIPELINE_ORCH_ROTATION_FILE"] = "/dev/null"
            # 2026-08-21 óta a script-default `fallback_engine=none` (a GPT
            # kvóta elfogyott), az ADR 0115 gépezete viszont változatlan —
            # ezért ez a cella EXPLICIT env-vel éleszti fel a Codex-oldalt.
            env["PIPELINE_FALLBACK_ENGINE"] = "terra"
            block = state / "claude-blocked-until"

            default = self.run_command(["bash", str(script), "--orchestrator-engine"], env=env)
            block.write_text("4102444800\n")   # 2100-01-01: érvényes zárlat
            blocked = self.run_command(["bash", str(script), "--orchestrator-engine"], env=env)
            block.write_text("1000000000\n")   # 2001: lejárt zárlat
            expired = self.run_command(["bash", str(script), "--orchestrator-engine"], env=env)
            expired_file_cleaned = not block.exists()
            block.write_text("4102444800\n")
            switched_off = self.run_command(
                ["bash", str(script), "--orchestrator-engine"],
                env={**env, "PIPELINE_FALLBACK_ENGINE": "none"},
            )

            self.assertEqual(default.stdout.strip(), "claude")
            self.assertEqual(blocked.stdout.strip(), "terra")
            self.assertEqual(expired.stdout.strip(), "claude")
            self.assertTrue(expired_file_cleaned, "a lejárt zárlatot a driver takarítja")
            self.assertEqual(switched_off.stdout.strip(), "claude")

    def test_the_default_orchestrator_is_claude_even_under_a_block(self) -> None:
        # USER-DÖNTÉS 2026-08-21 („lejárt a GPT kvóta"): rotáció-env nélkül a
        # review-t a Claude viszi, és ezt a Claude-zárlat SEM billenti át egy
        # Codex-oldali székre — az `fallback_engine=none` default alatt nincs
        # hová billenni, a lánc inkább kivárja a Claude-ablakot (a régi,
        # kvóta-tudatos halt-út). Az átbillenés gépezetét a fenti
        # `test_orchestrator_falls_back_to_terra_only_while_claude_is_blocked`
        # méri, explicit `PIPELINE_FALLBACK_ENGINE=terra` mellett.
        script = ROOT / "tools" / "round-pipeline.sh"
        with tempfile.TemporaryDirectory() as directory_name:
            state = Path(directory_name)
            env = {
                key: value
                for key, value in os.environ.items()
                if not key.startswith("PIPELINE_")
            }
            env["PIPELINE_STATE_DIR"] = str(state)

            default = self.run_command(["bash", str(script), "--orchestrator-engine"], env=env)
            (state / "claude-blocked-until").write_text("4102444800\n")
            blocked = self.run_command(["bash", str(script), "--orchestrator-engine"], env=env)

            self.assertEqual(default.stdout.strip(), "claude")
            self.assertEqual(blocked.stdout.strip(), "claude")

    def test_only_real_quota_messages_trigger_the_engine_switch(self) -> None:
        script = ROOT / "tools" / "round-pipeline.sh"
        quota_logs = (
            "Claude usage limit reached. Your limit will reset at 3pm.",
            "Error: quota exceeded for this organization",
            "You are out of credits — upgrade to continue",
        )
        # Hamis pozitív ellen: a promptok maguk beszélnek kvótáról és limitről.
        innocent_logs = (
            "a kvóta helyreállása után ugyanaz a task folytatható",
            "MiniMax 429/quota/5xx esetén nem indíthatsz közvetlen fallbacket",
            "Traceback (most recent call last): RuntimeError: gate failed",
        )
        with tempfile.TemporaryDirectory() as directory_name:
            log_file = Path(directory_name) / "session.log"
            for text in quota_logs:
                with self.subTest(quota=text):
                    log_file.write_text(text)
                    hit = self.run_command(
                        ["bash", str(script), "--claude-limit-check", str(log_file)]
                    )
                    self.assertEqual(hit.returncode, 0)
            for text in innocent_logs:
                with self.subTest(innocent=text):
                    log_file.write_text(text)
                    miss = self.run_command(
                        ["bash", str(script), "--claude-limit-check", str(log_file)]
                    )
                    self.assertNotEqual(miss.returncode, 0)

    def test_codex_preamble_maps_the_claude_only_concepts(self) -> None:
        preamble = (
            ROOT / "docs" / "execution" / "pipeline-codex-orchestrator-preamble.md"
        ).read_text()
        # A Codexnek nincs skill-rendszere: a skilleket fájlként kell olvasnia.
        self.assertIn(".claude/skills/sdd-round-driver/SKILL.md", preamble)
        self.assertIn(".claude/skills/sdd-round-review/SKILL.md", preamble)
        self.assertIn("AGENTS.md", preamble)
        # A kapu és a jelzés-kötelezettség nem lazul a másik motoron sem.
        self.assertIn("zöld kapu", preamble)
        self.assertIn("kör-jelzés", preamble)

    def test_fallback_launches_terra_home_and_keeps_implementer_routing(self) -> None:
        driver = (ROOT / "tools" / "round-pipeline.sh").read_text()
        # A Terra a saját CODEX_HOME-jában él (ott a default gpt-5.6-terra).
        self.assertIn("CODEX_HOME=$codex_home", driver)
        self.assertIn(".codex-terra", driver)
        # MÉRVE 2026-08-02: `codex exec` a pane TTY-járól "Reading additional
        # input from stdin..."-nel VÁRAKOZIK, ha a stdin nyitva marad — a
        # tmux-ban indított fallback így örökre beragadna.
        self.assertIn("< /dev/null", driver.split("codex_bin exec", 1)[1][:200])
        # Az implementer-routing (sor `engine` oszlopa + ADR 0088 router) NEM
        # változhat a review-motor fallbackjétől — user-döntés 2026-08-02.
        self.assertIn("validate_engine \"$engine\"", driver)
        self.assertIn("ai-router-round.sh", driver)

    def make_fake_worktree(self, directory: Path) -> tuple[Path, Path, Path]:
        worktree = directory / "worktree"
        (worktree / "tools").mkdir(parents=True)
        (worktree / "docs" / "rounds").mkdir(parents=True)
        shutil.copy2(ROOT / "tools" / "ai-router-round.sh", worktree / "tools" / "ai-router-round.sh")
        shutil.copy2(ROOT / "tools" / "codex-signal.sh", worktree / "tools" / "codex-signal.sh")
        brief = worktree / "docs" / "rounds" / "e03-r01-fake.md"
        brief.write_text("# Fake task\n")
        fake_router = worktree / "tools" / "model-router.py"
        fake_router.write_text(
            "#!/usr/bin/env python3\n"
            "import json, os, sys\n"
            "from pathlib import Path\n"
            "counter = Path(os.environ[\"FAKE_ROUTER_COUNT\"])\n"
            "count = int(counter.read_text()) if counter.exists() else 0\n"
            "counter.write_text(str(count + 1))\n"
            "result = Path(sys.argv[sys.argv.index(\"--result-json\") + 1])\n"
            "status = os.environ.get(\"FAKE_ROUTER_STATUS\", \"READY_FOR_REVIEW\")\n"
            "reason = os.environ.get(\"FAKE_ROUTER_REASON\", \"fake result\")\n"
            "codes = {\"READY_FOR_REVIEW\": 0, \"STOPPED\": 20, \"DEFERRED\": 30, \"BLOCKED\": 40, \"INTERNAL_ERROR\": 50}\n"
            "result.parent.mkdir(parents=True, exist_ok=True)\n"
            "result.write_text(json.dumps({\"schema_version\": 1, \"status\": status, \"reason\": reason}))\n"
            "raise SystemExit(codes[status])\n"
        )
        fake_router.chmod(0o755)
        subprocess.run(["git", "init", "-q"], cwd=worktree, check=True)
        subprocess.run(["git", "config", "user.email", "pipeline@example.invalid"], cwd=worktree, check=True)
        subprocess.run(["git", "config", "user.name", "Pipeline Test"], cwd=worktree, check=True)
        subprocess.run(["git", "add", "."], cwd=worktree, check=True)
        subprocess.run(["git", "commit", "-qm", "baseline"], cwd=worktree, check=True)
        return worktree, brief, fake_router

    def test_auto_adapter_dispatches_fake_router_once_and_redacts_status(self) -> None:
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            worktree, brief, _ = self.make_fake_worktree(directory)
            counter = directory / "count"
            result_json = worktree / ".ai" / "runs" / "E03-R01" / "router-result.json"
            mirror = directory / "router-status"
            env = dict(os.environ)
            env.update(
                FAKE_ROUTER_COUNT=str(counter),
                FAKE_ROUTER_STATUS="READY_FOR_REVIEW",
                FAKE_ROUTER_REASON="Authorization: Bearer top-secret " + "x" * 800,
                PIPELINE_ROUTER_STATUS_FILE=str(mirror),
            )

            completed = self.run_command(
                [
                    "bash",
                    str(worktree / "tools" / "ai-router-round.sh"),
                    "run",
                    str(worktree),
                    str(brief.relative_to(worktree)),
                    str(result_json),
                ],
                cwd=worktree,
                env=env,
            )

            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertEqual(counter.read_text(), "1")
            signal = (worktree / ".codex-round-status").read_text()
            self.assertIn("status=progress", signal)
            self.assertIn("router_status=READY_FOR_REVIEW", signal)
            self.assertNotIn("top-secret", signal)
            self.assertLess(len(signal), 1200)
            self.assertEqual(mirror.read_text(), signal)

    def test_signal_resolves_git_state_from_the_worktree_not_the_callers_cwd(self) -> None:
        # Mért reprodukció (E02-R21, H6, docs/LESSONS.md L42): az
        # orchestrátor a SAJÁT checkoutjából, `cd` nélkül, abszolút
        # útvonalon hívja a `codex-signal.sh`-t (lásd
        # `tools/ai-router-round.sh:50`) -- a `git rev-parse
        # --show-toplevel` a hívó folyamat öröklött cwd-jét oldja fel, nem a
        # munkapéldányt, ezért a `branch=`/`head=`/`dirty_files=` mezők a
        # ROSSZ repót mérték.
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            worktree, _, _ = self.make_fake_worktree(directory)
            subprocess.run(["git", "checkout", "-qb", "round-branch"], cwd=worktree, check=True)
            (worktree / "marker.txt").write_text("round work\n")
            subprocess.run(["git", "add", "marker.txt"], cwd=worktree, check=True)
            subprocess.run(["git", "commit", "-qm", "round work"], cwd=worktree, check=True)
            worktree_head = subprocess.run(
                ["git", "rev-parse", "--short", "HEAD"],
                cwd=worktree,
                check=True,
                text=True,
                capture_output=True,
            ).stdout.strip()

            caller = directory / "caller-repo"
            caller.mkdir()
            subprocess.run(["git", "init", "-q"], cwd=caller, check=True)
            subprocess.run(["git", "config", "user.email", "caller@example.invalid"], cwd=caller, check=True)
            subprocess.run(["git", "config", "user.name", "Caller"], cwd=caller, check=True)
            (caller / "readme.txt").write_text("unrelated repo\n")
            subprocess.run(["git", "add", "readme.txt"], cwd=caller, check=True)
            subprocess.run(["git", "commit", "-qm", "unrelated"], cwd=caller, check=True)

            script = worktree / "tools" / "codex-signal.sh"
            completed = self.run_command(
                ["bash", str(script), "progress", "safe summary"], cwd=caller
            )

            self.assertEqual(completed.returncode, 0, completed.stderr)
            signal = (worktree / ".codex-round-status").read_text()
            self.assertIn("branch=round-branch", signal)
            self.assertIn(f"head={worktree_head}", signal)

    def test_router_status_mapping_is_stable(self) -> None:
        expected = {
            "READY_FOR_REVIEW": "progress",
            "STOPPED": "stopped",
            "DEFERRED": "blocked",
            "BLOCKED": "blocked",
            "INTERNAL_ERROR": "blocked",
        }
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            worktree, _, _ = self.make_fake_worktree(directory)
            script = worktree / "tools" / "codex-signal.sh"
            for router_status, signal_status in expected.items():
                with self.subTest(router_status=router_status):
                    completed = self.run_command(
                        ["bash", str(script), router_status, "safe summary"], cwd=worktree
                    )
                    self.assertEqual(completed.returncode, 0, completed.stderr)
                    signal = (worktree / ".codex-round-status").read_text()
                    self.assertIn(f"status={signal_status}", signal)
                    self.assertIn(f"router_status={router_status}", signal)

    def test_pipeline_status_only_prints_sanitized_router_signal(self) -> None:
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            state = directory / "state"
            state.mkdir()
            (state / "router-status").write_text(
                "status=progress\nrouter_status=READY_FOR_REVIEW\nsummary=redacted safe\n"
                "unexpected_prompt=do not print me\n"
            )
            queue = directory / "queue.tsv"
            queue.write_text("E03-R01\tdocs/brief.md\tauto\t0089\tpending\n")
            env = dict(os.environ)
            env.update(PIPELINE_STATE_DIR=str(state), PIPELINE_QUEUE_FILE=str(queue))

            completed = self.run_command(
                ["bash", str(ROOT / "tools" / "pipeline-status.sh")], env=env
            )

            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertIn("READY_FOR_REVIEW", completed.stdout)
            self.assertNotIn("do not print me", completed.stdout)

    def test_codex_cli_usage_limit_summary_is_not_caught_by_the_terra_daily_budget_hold(
        self,
    ) -> None:
        # MÉRT gyökérok (E05-R15 H6, 2026-08-07T16:46:20Z): a fix-round-2
        # Codex/Terra dispatch a Codex CLI SAJÁT upstream usage-limitjébe
        # futott (`ERROR: You've hit your usage limit... try again at Aug
        # 8th, 2026 7:32 AM`, 3x azonos szöveg, .pipeline/HALTED) — ez
        # MÁS réteg, mint a `terra_hold_if_exhausted` által lekérdezett
        # router-belső napi hívás-számláló (`terra-status`,
        # `.ai/router.toml` `max_automatic_terra_calls_per_utc_day`, 2026-08-02
        # óta 0 = korlátlan). Ez a teszt a VALÓDI E05-R15 halt-summary-t adja
        # a meglévő `terra_hold_if_exhausted`-nek, egy a MOST ÉLES,
        # korlátlan router-policy-t szimuláló python3-stubbal — a régi
        # mechanizmus emiatt NEM ír holdot, ami a mért H6 gyökérokot
        # dokumentálja (a hiba nem a hívásban van, hanem abban, hogy erre a
        # jelre semmilyen hold-mechanizmus nem figyelt, l.
        # `test_codex_usage_limit_reset_epoch_is_parsed_from_the_real_e05_r15_halt_text`
        # alább — az ÚJ, kiegészítő mechanizmus ugyanerről a szövegről MÁR ír
        # holdot).
        script = ROOT / "tools" / "round-pipeline.sh"
        real_python3 = shutil.which("python3")
        self.assertIsNotNone(real_python3, "python3 kell a teszthez")
        with tempfile.TemporaryDirectory() as directory_name:
            state = Path(directory_name)
            stub_bin = state / "bin"
            stub_bin.mkdir()
            stub = stub_bin / "python3"
            stub.write_text(
                "#!/bin/sh\n"
                "case \"$*\" in\n"
                "  *model-router.py*terra-status*)\n"
                "    printf '{\"unlimited\": true, \"exhausted\": false}'\n"
                "    exit 0\n"
                "    ;;\n"
                "  *)\n"
                f"    exec {real_python3} \"$@\"\n"
                "    ;;\n"
                "esac\n"
            )
            stub.chmod(0o755)
            env = dict(os.environ)
            env["PIPELINE_STATE_DIR"] = str(state)
            env["PATH"] = f"{stub_bin}:{env['PATH']}"

            result = self.run_command(
                ["bash", str(script), "--terra-hold-if-exhausted", "E05-R15"], env=env
            )

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertFalse(
                (state / "terra-budget-hold").exists(),
                "a router napi-budget hold nem véletlenül maradt üres — ez a MÉRT "
                "bizonyíték arra, hogy a Codex CLI upstream usage-limitje nem ugyanaz "
                "a jel, mint a router belső napi számlálója",
            )

    def test_codex_usage_limit_reset_epoch_is_parsed_from_the_real_e05_r15_halt_text(
        self,
    ) -> None:
        script = ROOT / "tools" / "round-pipeline.sh"

        result = self.run_command(
            [
                "bash",
                str(script),
                "--codex-usage-limit-reset-epoch",
                REAL_E05_R15_CODEX_USAGE_LIMIT_SUMMARY,
            ]
        )

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(
            result.stdout.strip(), str(REAL_E05_R15_CODEX_USAGE_LIMIT_RESET_EPOCH)
        )

    def test_codex_usage_limit_reset_epoch_from_text_ignores_unrelated_summaries(
        self,
    ) -> None:
        # Őrszem a túl széles illeszkedés ellen: sem egy sima "quota"/"usage
        # limit" említés dátum nélkül, sem egy teljesen más halt-summary nem
        # termelhet hold-fájlt.
        script = ROOT / "tools" / "round-pipeline.sh"
        for unrelated in (
            "the CI runner is degraded, GitHub Actions incident",
            "quota concerns were discussed but nothing is exhausted right now",
            "usage limit dashboard reviewed, all green",
        ):
            with self.subTest(summary=unrelated):
                result = self.run_command(
                    ["bash", str(script), "--codex-usage-limit-reset-epoch", unrelated]
                )
                self.assertEqual(result.returncode, 1)
                self.assertEqual(result.stdout, "")

    def test_first_halt_detection_writes_the_codex_usage_limit_hold_without_waiting_for_a_selfheal_retry(
        self,
    ) -> None:
        # Testvér-teszt: `test_first_halt_detection_writes_the_terra_hold_without_waiting_for_a_selfheal_retry`
        # ugyanezt a mintát méri a router-belső Terra-holdra. Itt a HALT ELSŐ
        # észlelése (`handle_round_halt`, mielőtt bármilyen self-heal session
        # elindulna) a VALÓDI E05-R15 round-status szöveget kapja — a
        # `codex-usage-limit-hold` fájlnak MÁR ekkor ki kell íródnia, nem
        # várhat egy retry-klasszifikációra (ugyanaz a mért hiba-osztály, mint
        # a Terra-holdnál: E03-R08 H6, 5. javítás).
        script = ROOT / "tools" / "round-pipeline.sh"
        real_python3 = shutil.which("python3")
        self.assertIsNotNone(real_python3, "python3 kell a teszthez")
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            stub_bin = directory / "bin"
            stub_bin.mkdir()
            stub = stub_bin / "python3"
            stub.write_text(
                "#!/bin/sh\n"
                "case \"$*\" in\n"
                "  *model-router.py*terra-status*)\n"
                "    printf '{\"unlimited\": true, \"exhausted\": false}'\n"
                "    exit 0\n"
                "    ;;\n"
                "  *)\n"
                f"    exec {real_python3} \"$@\"\n"
                "    ;;\n"
                "esac\n"
            )
            stub.chmod(0o755)
            status_file = directory / "round-status"
            status_file.write_text(
                "outcome=halted\n"
                "round=E05-R15\n"
                "halt=H6\n"
                f"summary={REAL_E05_R15_CODEX_USAGE_LIMIT_SUMMARY}\n"
            )
            session_log = directory / "session-E05-R15-test.log"
            session_log.write_text("")
            env = dict(os.environ)
            env["PIPELINE_STATE_DIR"] = str(directory)
            env["PATH"] = f"{stub_bin}:{env['PATH']}"

            result = self.run_command(
                [
                    "bash",
                    str(script),
                    "--handle-round-halt",
                    "E05-R15",
                    str(status_file),
                    str(session_log),
                ],
                env=env,
            )

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertTrue((directory / "HALTED").exists())
            hold_file = directory / "codex-usage-limit-hold"
            self.assertTrue(
                hold_file.exists(),
                "a HALT első észlelése nem írta ki a Codex-usage-limit holdot — a "
                "következő firing önjavítási kísérlet elköltése nélkül újra "
                "nekifutna ugyanennek a Codex CLI kvóta-falnak",
            )
            content = hold_file.read_text()
            self.assertIn("round=E05-R15", content)
            self.assertIn(
                f"hold_until={REAL_E05_R15_CODEX_USAGE_LIMIT_RESET_EPOCH}", content
            )

    def test_codex_usage_limit_hold_blocks_a_firing_without_spending_a_selfheal_attempt(
        self,
    ) -> None:
        # Testvér-teszt: `test_terra_budget_hold_blocks_a_firing_without_spending_a_selfheal_attempt`
        # ugyanezt méri a router-belső Terra-holdra — ugyanaz a
        # biztonsági indoklás vonatkozik: `selfheal.count` SZÁNDÉKOSAN a
        # kísérletbüdzsé HATÁRÁN (3) ül, hogy egy esetleges regresszió a már
        # biztonságos "KIMERÜLT" rövidzárba fusson (session nélkül), SOSEM egy
        # ÉLES tmux+claude önjavító session indításába ez ellen a valódi
        # repó ellen.
        script = ROOT / "tools" / "round-pipeline.sh"
        with tempfile.TemporaryDirectory() as directory_name:
            state = Path(directory_name)
            (state / "HALTED").write_text(
                "round=E05-R15\n"
                "halt=H6\n"
                f"summary={REAL_E05_R15_CODEX_USAGE_LIMIT_SUMMARY}\n"
            )
            future = int(time.time()) + 3600
            (state / "codex-usage-limit-hold").write_text(
                f"round=E05-R15\nhold_until={future}\n"
            )
            (state / "selfheal.count").write_text("E05-R15|H6|3\n")
            env = dict(os.environ)
            env.update(
                PIPELINE_STATE_DIR=str(state),
                PIPELINE_SELFHEAL_MAX="3",
                # MÉRVE (l. a testvér-teszt indoklása): egy tiszta `main`-ről
                # futtatott teljes firing éles sessiont indítana, ha a hold
                # valamiért mégsem fogná el a firing-ot.
                PIPELINE_NO_LAUNCH="1",
            )

            held = self.run_command(["bash", str(script)], env=env)

            self.assertEqual(held.returncode, 0, held.stderr)
            self.assertIn("felfüggesztés aktív", held.stderr)
            self.assertNotIn("ÖNJAVÍTÓ KÖR indul", held.stderr)
            self.assertNotIn("KIMERÜLT", held.stderr)
            self.assertEqual((state / "selfheal.count").read_text(), "E05-R15|H6|3\n")
            self.assertTrue((state / "HALTED").exists())


class NoLaunchGuardTest(unittest.TestCase):
    """`PIPELINE_NO_LAUNCH=1` must make a session launch impossible.

    MÉRT incidens (2026-08-05, GOV-03): a teljes firinget futtató esetek
    izolált `PIPELINE_STATE_DIR`-t kapnak, de a kör-indítási ág a VALÓDI
    `docs/execution/pipeline-queue.tsv`-t olvassa. Tiszta `main`-ről futtatva
    a suite ÉLES orchestrátor-sessiont és `codex exec`-et indított az
    E04-R10-re; a félkész implementer-munka elveszett, a kör-branchet újra
    pre-flightolta és pusholta. A tesztfájl korábbi fejlécei ezt a veszélyt
    már ismerték, de csak a self-heal ágra védekeztek stub-okkal — a
    kör-indítási ág védtelen maradt.

    Ezért a védelem nem stub, hanem szerződés a driverben; ez a teszt azt
    méri, hogy a szerződés a KÓDBAN van, nem a tesztek fegyelmében.
    """

    def test_the_driver_refuses_to_start_any_session_under_the_switch(self) -> None:
        source = (ROOT / "tools" / "round-pipeline.sh").read_text(encoding="utf-8")

        # A kapcsolót a KÖZÖS session-indító őrzi, tehát a kör- és az
        # önjavító ág is fedve van egyetlen ponton.
        launcher = source.split("run_tmux_session() {", 1)[1]
        guard_position = launcher.find('PIPELINE_NO_LAUNCH')
        tmux_position = launcher.find('tmux new-session')

        self.assertNotEqual(guard_position, -1, "hiányzik a PIPELINE_NO_LAUNCH őr")
        self.assertNotEqual(tmux_position, -1, "nem található a session-indítás")
        self.assertLess(
            guard_position,
            tmux_position,
            "az őrnek a session-indítás ELŐTT kell visszatérnie",
        )

    def test_every_full_firing_test_sets_the_switch(self) -> None:
        # Regressziós őr: ha valaki új teljes-firing esetet ír a kapcsoló
        # nélkül, ez a teszt elhasal, mielőtt élesben indítana kört.
        source = (ROOT / "tools" / "tests" / "test_pipeline_integration.py").read_text(
            encoding="utf-8"
        )
        full_firings = source.count('run_command(["bash", str(script)], env=env)')

        self.assertEqual(
            source.count('PIPELINE_NO_LAUNCH="1"'),
            full_firings,
            "minden teljes-firing esetnek PIPELINE_NO_LAUNCH=1-gyel kell futnia",
        )


if __name__ == "__main__":
    unittest.main()
