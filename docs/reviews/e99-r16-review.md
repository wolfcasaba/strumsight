# E99-R16 — Review

Brief: `docs/rounds/e99-r16-gov-10-round-granularity.md` (§0.0 pre-flight R1–R5)
Diff: `git diff d26e7655 f416f959` (`main`→`minimax/e99-r16-round-granularity`)
Reviewer: Claude (orchestrátor) · Dátum: 2026-08-19
Verdikt: CHANGES REQUIRED

**Upstream-szinkron a review UTÁN:** a review az `f416f959` fejen (izolált
`/tmp/review-e99-r16` klón) készült. Közben egy PÁRHUZAMOS, független
önjavító session (E07-R25/H5, `.pipeline/inflight/E07-R25`, teljesen
diszjunkt `allowed_paths`) `a1613fa5`/`e041e384`-et merge-elte az
`origin/main`-re — ennek egyik fájlja pont a pre-flight R4-ben dokumentált,
kör-független `tools/tests/test_knowledge_rag.py` hibát javította (a
fixtúrát szintetikus brief-re cserélte, ugyanazzal a gyökérokkal, amit R4
mért). A kör-branch ezt már `--no-ff` merge-eltük és push-oltuk
(`0007d5f0`) a §0.3 eljárás szerint — a pre-flight R4 kivétel emiatt a
KÖVETKEZŐ teljes-suite futáson várhatóan eltűnik (a lenti gate-bizonyíték
tábla az `f416f959`-ös állapotot rögzíti; a javító kör utáni újramérés a
`0007d5f0`+javítás fejen fut, és ott már csak F2/F3 várható R4 helyett).

## Összegzés

BLOCKER: 0 · MAJOR: 2 · MINOR: 2 · NOTE: 2 · Scope-gap (nem javítható ebben a körben): 1

## Acceptance criteria (Definition of Done)

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | D1–D3 kész; `--granularity`/`brief-merge-plan.py` determinisztikus fixtúra-kimenet | ⚠️ RÉSZBEN | D1/D3 helyesek (mérve, ld. lent). D2 CRASH-el a brief §3 saját mondata szerinti fő használati módban (`--with-regression`) — F1. |
| 2 | `python3 tools/brief-lint.py --open --level base` → 0 lelet | ✅ | Élesben lefuttatva az izolált klónban: „nincs lelet”, exit 0. |
| 3 | `python3 -m pytest tools/tests -q` zöld | ❌ | 3 hiba, ebből 1 a kör diffjétől FÜGGETLEN, előre dokumentált (pre-flight R4); **2 ÚJ, a kör diffje által OKOZOTT** hiba (F2, F3). Ld. „Gate-bizonyíték” lent. |
| 4 | `tools/round-gate.sh test/tooling/architecture_allowlist_guard_test.dart` zöld | ✅ | Izolált klónban lefuttatva: mind a 6 lépés (format/analyze/test/architecture/secrets/l10n) ZÖLD. |
| 5 | Kör-jelzés `done` | ✅ | `.codex-round-status`: `status=done`, `branch=main` (→ az orchestrátor átnevezte `minimax/e99-r16-round-granularity`-re, ld. Scope-audit), `dirty_files=1` a jelzés pillanatában, de a munkafa a review-klónozáskor tisztán, mind az 5 commit commitolva. |

## Scope-audit

`tools/scope-audit.py --repo <klón> --brief docs/rounds/e99-r16-gov-10-round-granularity.md --base d26e7655` → **OK**, 5 megváltozott útvonal, mind az `allowed_paths`-on (0 generated/ignored, 0 VIOLATION).

**Folyamat-megjegyzés (nem tartalmi lelet):** az implementer a saját, izolált munkapéldányában közvetlenül a lokális `main` ágra commitolt a dedikált kör-ág helyett (`branch=main` a jelzésben). Az orchestrátor ezt a review ELŐTT helyben javította: `git branch minimax/e99-r16-round-granularity f416f959` + a lokális `main` visszaállítva `d26e7655`-re (az origin `main`-t ez nem érintette, oda semmi nem lett push-olva a javítás előtt). A branchen kívül ez nem hagyott nyomot; a jövőbeli MiniMax-promptba érdemes explicit "hozz létre és válts a `minimax/<kör>` ágra az első lépésként" utasítást tenni — ezt a HANDOFF-ba/lecke-korpuszba viszem.

## Megállapítások

### F1 — MAJOR — `brief-merge-plan.py` összeomlik a `--with-regression` útvonalon (a D2 saját fő specifikált forgatókönyve)

- **Fájl:** `tools/brief-merge-plan.py:252`
- **Probléma:** `f"becsült megtakarítás: {estimate['saved_minutes']:.0p}p fix overhead"` — a `.0p` NEM érvényes Python format-spec (nincs `p` presentation type floatra). Bármikor lefut, amikor `estimate['saved_minutes'] is not None`, azaz amikor VAN `--with-regression` bemenet ÉS legalább egy jelölt pár teljesíti mind a négy feltételt.
- **Hatás:** `ValueError: Unknown format code 'p' for object of type 'float'`, a program `exit 1`-gyel összeomlik — ez a brief §3 saját szövege szerint a tool FŐ, dokumentált kimeneti módja („A kimenet minden párnál megadja a mért indokot… a D1 illesztésből”), és a `--with-regression` az EGYETLEN módja, hogy ez a mező valaha kitöltődjön.
- **Ellenőrzés (élő reprodukció, kétszer, VALÓDI adaton):**
  ```
  $ python3 tools/round-metrics.py --chain-log .pipeline/chain.log --granularity --format json > /tmp/real-regression.json
  $ python3 tools/brief-merge-plan.py --with-regression <(python3 -c "...d['regression']...") --format text
  Traceback ...
  ValueError: Unknown format code 'p' for object of type 'float'
  ```
  Szintetikus fixtúrán (E07-R01/E07-R02 pár, `intercept=40.0, slope=2.5`) ugyanaz a crash. **Egyik ÚJ teszt sem hívja a `--with-regression` kapcsolót** — a mérce-mátrix (brief §4) ezt nem írta elő explicit módon, de a hiba így 0 teszttel csúszott át.
- **Kötelező javítás:** `.0p` → `.0f` (a `saved_minutes` már perc-mértékegységű float — ld. F-jegyzet a `_estimate_pair_seconds` névadásáról is).
- **Ellenőrzés a javításhoz:** legalább egy ÚJ teszt, ami `--with-regression`-nel hív egy VALÓDI jelölt párt, és a `rationale`/`regression_basis` mezőt ellenőrzi (nem csak az exit code-ot) — enélkül a hiba megismétlődhet egy jövőbeli refaktornál.
- **Státusz:** OPEN

### F2 — MAJOR — `round-metrics.py` új top-level importja eltöri a meglévő „másold és futtasd önállóan” falszifikációs mintát

- **Fájl:** `tools/round-metrics.py:38-41` (`from tools.ai_router.brief import ...` feltételes `sys.path.insert`-tel)
- **Probléma:** a `sys.path.insert(0, str(Path(__file__).resolve().parent.parent))` a `__file__` SAJÁT helyétől számol — ha a fájlt egy MÁS könyvtárba másolják és onnan futtatják (ez a `tools/tests/test_round_metrics_engines.py` egyik LÉTEZŐ, ELŐZŐ körökből örökölt tesztmintája: `shutil.copy(SCRIPT, tempdir/"round-metrics.py")`, majd `[sys.executable, str(script_copy), ...]`), a `tools` csomag nem található.
- **Hatás:** **MEGSZAKÍTOTT, ELŐZŐLEG ZÖLD teszt** (nem a pre-flight R4 kör-független hibája — ez ÚJ, a kör diffje okozza): `tools/tests/test_round_metrics_engines.py::EnginesOutlierFalsificationTest::test_kiugro_szures_kivetelevel_a_median_teszt_piros` — a D1 §4 falszifikációs cellájának TESZTVÉDELME ez a fájl, tehát pont az a mechanizmus sérül, ami a JELEN kör saját kiugró-szűrését is védi máshol.
- **Ellenőrzés (élő reprodukció):**
  ```
  $ cp tools/round-metrics.py /tmp/repro-copy/round-metrics.py
  $ python3 /tmp/repro-copy/round-metrics.py --chain-log /dev/null --engines --format json
  ModuleNotFoundError: No module named 'tools'
  ```
- **Kötelező javítás:** az importot tegye a `load_briefs_for_queue` függvény BELSEJÉBE (lokális import), ne modul-szintre — a `--engines`/`--cost`/alapértelmezett táblázat útvonal így önálló script-ként (repo-fán kívül másolva is) változatlanul fut, csak a `--granularity` (ami ÚGYIS a repo-fát olvassa a brief-ekhez) igényli ténylegesen a `tools.ai_router.brief`-et.
- **Ellenőrzés a javításhoz:** a fenti `cp` + önálló futtatás próba piros→zöld, ÉS a teljes `tools/tests` újra lefuttatva megerősíti, hogy `test_round_metrics_engines.py` mind a 7 tesztje zöld marad.
- **Státusz:** OPEN

### F3 — Scope-gap, NEM javítható ebben a körben — hiányzó Router CI path-fedezet az új `tools/brief-merge-plan.py`-ra

- **Fájl:** `.github/workflows/router-ci.yml` (`paths:` blokk) — **NINCS** a kör `allowed_paths`-án, és a `.github/`-ot ez az orchesztrátor-session a saját szabálya szerint SOSEM módosítja (pipeline-prompt §4 — „a mérce nem módosulhat attól, akit mér”).
- **Probléma:** `tools/tests/test_router_ci_path_filter.py::test_every_test_referenced_file_is_in_the_ci_filter` PIROS: a `tools/brief-merge-plan.py`-t a `tools/tests` csomag hivatkozza (van rá guard-teszt: `test_brief_merge_plan.py`), de a `router-ci.yml` `paths:` szűrője nem tartalmazza — egy jövőbeli, KIZÁRÓLAG ezt a fájlt érintő push nem indítana Router CI-t.
- **Hatás mértéke:** **ezt a kört magát nem blokkolja end-to-end** — a kör saját diffje `docs/rounds/**`-ot is érinti, ami már lefedett minta, tehát a Router CI a SAJÁT push-unkra úgyis lefut (H5 szempontból nincs kockázat). A hiány kizárólag JÖVŐBELI, `tools/brief-merge-plan.py`-t ÖNMAGÁBAN érintő változásokra vonatkozik.
- **Miért mégis nyitva marad:** a DoD #3 (`pytest tools/tests -q` zöld) szó szerint nem teljesül, és a javítás egyetlen lehetséges helye tiltott zóna ennek a sessionnek. Ez pontosan a pipeline-prompt §4 által megnevezett eset: „ha az akadály éppen ott van [a `.github/`-ban], az HALT, és az önjavító kör dolga”.
- **Javasolt javítás (a self-healnek):** egyetlen sor felvétele a `router-ci.yml` `paths:` blokkjába: `"tools/brief-merge-plan.py"` (a meglévő egyenkénti-fájlos mintát követve, ahogy pl. `tools/model-router.py` is egyenként szerepel — NEM blanket `tools/**`, azt a `test_the_filter_has_no_dead_patterns` teszt driftté minősítené, ha egy hozzá nem tartozó path is illeszkedne).
- **Ellenőrzés a javításhoz:** `python3 -m unittest tools.tests.test_router_ci_path_filter -v` → mindkét teszt zöld.
- **Státusz:** OPEN (self-heal hatáskör)

### M1 — MINOR — méret-metrika inkonzisztencia D1 (regresszió-illesztés) és D2 (becslés-alkalmazás) között

- **Fájl:** `tools/round-metrics.py:301` (`_round_size = len(allowed_paths) + len(gate_tests)`, ez az X a regresszióhoz) vs. `tools/brief-merge-plan.py:224-229` (`_estimate_pair_seconds(len(left_metadata.allowed_paths), len(right_metadata.allowed_paths), ...)` — **gate_tests nélkül**).
- **Probléma:** a D1 által illesztett `slope`/`intercept` egy `allowed_paths+gate_tests` méretű X-tengelyre van kalibrálva, de a D2 ezt az illesztést egy CSAK-`allowed_paths` méretre alkalmazza vissza — minden becsült `left_minutes`/`right_minutes`/`saved_overhead_minutes` szisztematikusan torzul kb. `slope × gate_tests_count` perccel (a valós adaton mérve: `slope≈2.1p/fájl`, tipikusan 1 `gate_tests`-elem → ~2 perc torzítás páronként — kicsi, de a tool EGYETLEN célja a mért pontosság).
- **Kötelező javítás:** `_estimate_pair_seconds` hívása kapja meg `len(left_metadata.allowed_paths) + len(left_metadata.gate_tests)` (és ugyanígy a jobb oldalra).
- **Státusz:** OPEN (a körben javítható, kis diff)

### M2 — MINOR — D3 (S6 lelet) teszt-lefedettség nélkül a kör saját fájllistáján belül

- **Fájl:** `tools/brief-lint.py:346-370` (S6)
- **Probléma:** a brief `allowed_paths`-a KÉT új tesztfájlt nevez meg, mindkettőt D1/D2-nek dedikálva (`test_round_metrics_granularity.py`, `test_brief_merge_plan.py`) — D3-nak nincs saját tesztfájl-célpontja, a MEGLÉVŐ brief-lint-szabály tesztharness (`tools/tests/test_pipeline_throughput.py`) pedig NINCS ezen a listán (tiltott zóna erre a körre). Az implementer emiatt NEM tudott (és nem is próbált) S6-ra regressziós tesztet írni.
- **Függetlenül ellenőrizve (eldobható próba, NEM permanens teszt):** 1 munka-fájlos brief → S6 helyesen tüzel; 2 és 4 munka-fájlos brief → helyesen NEM tüzel (a határ inkluzív "2-nél kevesebb" szerint). A SZABÁLY tehát MŰKÖDIK, csak nincs jövőbeli regresszió ellen védve.
- **Javaslat:** ezt elfogadom változatlanul (nem növelem a diffet egy scope-on kívüli fájllal) — a hiányzó védelmet a HANDOFF/LESSONS rögzíti egy jövőbeli körnek. Ez a pre-flight (én) hibája is: a brief nem allokált tesztfájlt D3-nak.
- **Státusz:** WONTFIX ebben a körben (dokumentált tartozás, ld. HANDOFF)

## NOTE

- `tools/tests/test_round_metrics_granularity.py:19` — `import textwrap`, sosem használva. Kozmetikai, nem blokkol.
- `tools/brief-merge-plan.py:155` — `_estimate_pair_seconds` a nevében „seconds”, valójában PERCET számol és ad vissza (a hívó oldal helyesen percként kezeli). Csak elnevezési pontatlanság.

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| `tools/round-gate.sh test/tooling/architecture_allowlist_guard_test.dart` (izolált `/tmp/review-e99-r16` klón) | 6/6 lépés ZÖLD (format, analyze, test, architecture, secrets, l10n) | ✅ |
| `python3 tools/brief-lint.py --open --level base` | „nincs lelet”, exit 0 | ✅ |
| `python3 -m pytest tools/tests -q` (izolált venv, ugyanazon a klónon) | `3 failed, 545 passed, 1 skipped, 565 subtests passed` — 1 a pre-flight R4 szerint kör-független (`test_knowledge_rag.py` S8/E99-R15-done), **2 ÚJ, a kör diffje okozta** (F2 `test_round_metrics_engines.py`, F3 `test_router_ci_path_filter.py`) | ❌ (F1 önmagában nem jelenik meg itt, mert a mérce-mátrix nem ír elő `--with-regression` tesztet — F1-et külön, élő reprodukcióval mértem) |
| Falszifikációs cellák (brief §4) | D1 kiugró-szűrés: mutáció→PIROS→visszaállítás→ZÖLD (saját kézzel, `tools/round-metrics.py` `filtered = list(samples)` mutáció). D2 natív-gate kizárás: mutáció→PIROS→visszaállítás→ZÖLD (`tools/brief-merge-plan.py` feltétel törlése). | ✅ mindkettő valódi, nem kozmetikus |
| Valódi adaton (nem fixtúra) élő futtatás | `--granularity` a valódi `.pipeline/chain.log`-on: 136 minta, intercept≈82p, slope≈2.1p/fájl, R²=0.027 — értelmes, nem-hamis kimenet. `brief-merge-plan.py` a valódi sor-fájlon: 12 valódi jelölt pár (mind E08/gamification) — értelmes, nem-hamis kimenet. | ✅ |

## Merge-döntés

**Merge TILOS** (F1, F2 MAJOR nyitva; F3 scope-gap a DoD #3-at is megtöri). F1/F2 egy NORMÁL javító körben (ugyanaz a motor, MiniMax) javítható — mindkettő a jelen `allowed_paths`-on belüli fájlt érint. F3 javítása KÍVÜL esik ezen és minden jövőbeli, ugyanígy korlátozott orchesztrátor-session hatáskörén (`.github/` tiltott zóna) — F1/F2 javítása UTÁN ez marad az egyetlen nyitott tétel, és HALT (H3) útján, önjavító körnek adva oldódik fel.
