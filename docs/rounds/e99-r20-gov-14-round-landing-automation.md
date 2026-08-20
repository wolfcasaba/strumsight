# E99-R20 (GOV-14) — Landoló: rebase-őr, konfliktus-osztályozás és kapu a kombinált állapoton

- **Státusz:** READY FOR IMPLEMENTATION (pre-flight 2026-08-20, `main @ 909ea6c9`)
- **Típus:** **governance-kör** — a lánc SAJÁT vezérlése
- **Kör-azonosító:** `E99-R20`. Emberi neve **GOV-14**.
- **Előfeltétel:** nincs (a `tools/round-land.sh` új fájl; nem ütközik az E99-R14…R19 fájlhalmazával)
- **Brief szerzője:** Claude (Opus 5, orchesztrátor) · **ADR:** [`0313`](../adr/0313-round-landing-automation.md) — az ADR MÁR MEGÍRVA, a `docs/adr/` TILOS zóna.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "tools/round-land.sh",
  "tools/tests/test_round_land.py",
  "docs/execution/pipeline-orchestrator-prompt.md",
  # ".github/workflows/router-ci.yml" — TÁRGYTALAN (mérve 2026-08-19).
  # A kör CSAK `tools/` alá hoz létre fájlt, a workflow `paths:` blokkja
  # pedig már `tools/**` családi globot használ (PR #324), tehát a CI
  # lefedettség automatikus. A védett fájl ezért kikerült a listáról:
  # így a mérce-őr pre-flightja nem teszi hold-ra a kört.
  "docs/rounds/e99-r20-gov-14-round-landing-automation.md",
]
gate_tests = [
  "test/tooling/architecture_allowlist_guard_test.dart",
]
native_gate = false
```

> **Kockázat = high, indoklás:** a diff a `main`-re történő merge útjába nyúl.
> Egy hibás konfliktus-besorolás némán ronthat naplót vagy rossz oldalt
> tarthat meg. A `gate_tests` cella fa-egészség őr; a kör tényleges mércéje a
> `pytest tools/tests` + Router CI (§7).

## 0.0 Pre-flight revízió (Sol orchesztrátor, 2026-08-20)

- A strict brief-lint jelentés (`.pipeline/brief-lint-E99-R20.md`) **nem
  tartalmaz leletet**.
- Az ADR-számfoglaló a mai futásban `0346`-ot adott, mert az előre kiosztott
  [`ADR 0313`](../adr/0313-round-landing-automation.md) már elfogadva,
  verziózva és merge-elve van (`784e90e6`, PR #313). Ezért ez a kör **nem ír
  új ADR-t**, és a `docs/adr/**` tilos zóna változatlan. A generikus
  orchestrátor-prompt „te írod meg” mondata ennél az előre dokumentált
  governance-körnél stale; második, divergens ADR nem készül.
- A kódban újramérve: `tools/round-merge-lock.sh` kizárólag a zárat szerzi
  meg és a kapott parancsot futtatja; `tools/round-land.sh` továbbra sem
  létezik; a kimondott nyers merge-út a
  `docs/execution/pipeline-orchestrator-prompt.md:489` soron van (nem a brief
  korábbi 463. során).
- Az ADR 0242 óta a rebase utáni nyers, argumentum nélküli
  `git push --force-with-lease` tilos. A D1 ezért a meglévő
  `tools/safe-force-push.sh <branch>` artefaktumot hívja. Annak `3`-as
  kódja remote-only commitot bizonyít: ilyenkor a landoló fail-closed
  `blocked` jelzést ad és nem pushol/merge-el; nem próbálja kézzel felülírni
  a biztonságos push-protokollt.
- A D5 CI-lefedettség már teljesül: a
  `.github/workflows/router-ci.yml:31` alatti `tools/**` családi glob mind a
  landolót, mind a tesztjét lefedi. A workflow módosítása nem feladat; ezt a
  meglévő `tools/tests/test_router_ci_path_filter.py` és az exact-SHA Router
  CI bizonyítja.
- A kötelező RAG-sorrend (szűkített `lessons,halts,adr` → szűkített
  `lessons,halts` → teljes korpusz) friss, `909ea6c9` indexen futott.
  Releváns előzmény: `lessons/L77` (saját brief-konfliktusnál a friss main
  oldala nyer), `lessons/L253` (szöveges konfliktus és valódi logika
  szétválasztása), valamint `halts/E06-R23 H8` (a nyers lease-push
  adatvesztési kockázata). A teljes korpuszos keresés további közvetlen
  előzményt nem adott; az ADR 0313 és ez a brief volt a két első találat.
- **F1/F2 javítórevízió (2026-08-20):** az exact-SHA merge-előfeltételt
  szigorítja, az ADR 0313 scope-ját nem tágítja. A landoló minden invokáció
  elején strukturált PR-metaadatból köti a `main` base-et, a lokális current
  branch-et és az induló lokális HEAD-et. Ha a rebase új HEAD-et képez, a
  kombinált-HEAD gate és a safe push után merge nélkül `blocked` jelzéssel
  új exact-SHA CI-dispatch-t kér; csak a következő, változatlan és már
  igazolt HEAD-en futó invokáció merge-elhet.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. **STOP-protokoll:** listán kívüli fájl →
`stopped` + brief-revízió kérése; az `allowed_paths` tágítása TILOS.

## 0.1 Visszakeresett előzmény (tudás-index, ADR 0312 §4.1)

`node tools/knowledge-rag.mjs --top 6 "H8 rebase konfliktus merge landolás main elmozdult"`:

- **`lessons/L77`** (E03-R11 H8) — a rebase **kizárólag a kör saját briefjében**
  adott konfliktust; a feloldás elve: *a merge-elt `main` oldala az irányadó*,
  force-push nélkül.
- **`lessons/L82`** (E03-R12) — ugyanez az osztály: „brief-only
  rebase-konfliktus", a `main` scope-ját kell megőrizni.
- **`lessons/L253`** (E99-R08) — két függetlenül írt, funkcionálisan azonos
  javítás: a logika magától összefésülődött, **csak a komment szövege** ütközött.
- **`lessons/L126`** (E04-R15) — halted kört rebase-eléssel kell BEFEJEZNI, nem
  újraimplementálni.

Ezért mechanikus osztály **csak** a brief + a két append-only napló; minden más
marad H8 (ADR 0313 §2.1).

## 1. Cél — a mért 36 H8

A H8 („a `main` a dispatch óta mozdult, ÉS a rebase konfliktust ad") a
harmadik leggyakoribb halt-kódunk: **36 előfordulás** (H3: 136, H6: 129,
H2: 16). Mindegyik egy önjavító ciklust indít olyan munkára, amit a §0.1
leckéi szerint többségében mechanikusan meg lehet oldani.

A második, csendesebb rés: a CI a **rebase előtti** ágon fut, a merge a
**rebase utáni** állapotot viszi be. Mérve 2026-08-18: a PR #312 zöld CI
(`ce403a3a`) után `DIRTY` lett; a rebase utáni `ff01cfae` állapotot külön
futtatás nélkül is lehetett volna mergelni.

## 2. Jelenlegi állapot — mérve a kódban

- `tools/round-merge-lock.sh` sorosít, de csak zár: rebase-t, osztályozást,
  kaput nem futtat.
- `docs/execution/pipeline-orchestrator-prompt.md:489` a kimondott merge-út:
  `tools/round-merge-lock.sh gh pr merge <PR> --squash --delete-branch`.
- A H8 eljárás (prompt §, „rebase után mindig `--force-with-lease`, a
  visszautasítás önmagában nem H8") ma **prózában** él, gépi támasz nélkül.
- `tools/round-land.sh` nem létezik.

## 3. Feladatok

### D1 — `tools/round-land.sh` váz

```
tools/round-land.sh --pr <szám> --round <E99-R20> [--gate-test <útvonal>]…
```

Lépések sorrendben, a merge-záron BELÜL (a script maga hívja a
`tools/round-merge-lock.sh`-t, hogy a hívó ne felejthesse el):

1. `git fetch origin main`;
2. ha a branch már a friss `main` fölött van → 4. lépés;
3. `git rebase origin/main`; konfliktus esetén → D2;
4. **kapu a kombinált (rebase utáni) HEAD-en** → D3;
5. `tools/safe-force-push.sh <branch>`; `3`-as visszatérés (remote-only
   commit) vagy más push-hiba → `blocked`, nincs kézi/implicit lease-push;
6. Ha a rebase új HEAD-et képzett: `blocked` jelzés új exact-SHA
   CI-dispatch kérésével, merge nélkül. A következő, változatlan és már
   igazolt HEAD-en futó invokáció hívhat csak `gh pr merge <szám> --squash
   --delete-branch`-et.

Minden landing-gitművelet előtt a landoló `gh pr view --json` strukturált
metaadatából ellenőrzi, hogy `baseRefName == main`, `headRefName` a lokális
current branch, és `headRefOid` az invokáció induló lokális HEAD-je. Eltérés
fail-closed `blocked`: nincs fetch/rebase, push vagy merge.

Minden lépés naplózva: `.pipeline/land-<kör>.log` (csonkítatlan).

### D2 — Konfliktus-osztályozó (fail-closed)

- MECHANIKUS útvonalak, pontosan ez a három (ADR 0313 §2.1):
  `HANDOFF.md` (unió), `docs/LESSONS.md` (unió),
  `docs/rounds/<a kör saját briefje>` (**a `main` oldala nyer**).
- A kör saját briefje a `--round` értékéből származik, **nem** minta-illesztéssel
  az egész `docs/rounds/` fára: idegen kör briefje szemantikus.
- **Minden más útvonal szemantikus** → `git rebase --abort`, `blocked` jelzés
  a H8 szöveggel, a konfliktusos fájlok felsorolásával. Ismeretlen útvonal =
  szemantikus (fail-closed).
- Vegyes eset (mechanikus ÉS szemantikus fájl is ütközik) → **szemantikus**:
  abort, nincs részleges feloldás.
- Az unió-feloldás nem `git checkout --ours/--theirs`: mindkét oldal új
  szakaszának meg kell maradnia; a kimenetben nem maradhat konfliktus-jelölő.

### D3 — Kapu a kombinált állapoton

- A `--gate-test` értékek a kör `gate_tests` cellái; nulla darab esetén a
  landoló a fa-egészség őrt futtatja.
- `tools/round-gate.sh <tesztek>` a rebase-elt HEAD-en, csővezeték nélkül.
- Piros kapu → **nincs push, nincs merge**, `blocked` jelzés a kapu
  kimenetének útvonalával.

### D4 — Az orchesztrátor-prompt a landolóra mutat

`docs/execution/pipeline-orchestrator-prompt.md`: a merge-lépés a
`tools/round-land.sh`, a nyers `gh pr merge` már nem a kimondott út. A H8
szakasz megmarad, de kimondja, hogy a mechanikus osztályt a landoló kezeli, és
H8-ot már csak a szemantikus osztályra kell jelenteni.

### D5 — CI-szűrő (pre-flightban már teljesült, csak verifikáció)

A `.github/workflows/router-ci.yml` meglévő `tools/**` `paths:` globja lefedi
a `tools/round-land.sh` és `tools/tests/test_round_land.py` fájlokat. A kör
nem módosítja a workflow-t; a lefedettséget a meglévő
`tools/tests/test_router_ci_path_filter.py` és az exact-SHA Router CI méri.

## 4. Mérce-mátrix (`tools/tests/test_round_land.py`)

Hermetikus git-repókon (fixture: `origin` + branch, ne az élő fát), a `gh`
hívás injektált csonk:

| eset | bemenet | elvárt viselkedés |
|---|---|---|
| tiszta | a branch a friss `main` fölött | rebase kimarad, kapu fut, merge megtörténik |
| mechanikus — napló | `HANDOFF.md` mindkét oldalon új szakasz | unió: MINDKÉT szakasz benne, nincs `<<<<<<<`; a rebase-elt HEAD gate+safe push után új exact-SHA CI-t kér, az első hívás nem merge-el |
| mechanikus — brief | a kör saját briefje ütközik | a `main` oldala marad; a rebase-elt HEAD gate+safe push után új exact-SHA CI-t kér, az első hívás nem merge-el |
| szemantikus | `tools/round-pipeline.sh` ütközik | `rebase --abort`, `blocked`, NINCS merge |
| vegyes | `HANDOFF.md` **és** egy `.dart` forrás is ütközik | szemantikusként kezelve: abort, NINCS merge |
| ismeretlen útvonal | `docs/execution/valami-uj.md` ütközik | szemantikus (fail-closed), NINCS merge |
| piros kapu | rebase rendben, a kapu piros | NINCS push, NINCS merge, `blocked` |
| biztonságos push megtagadása | a remote branch-en új, remote-only commit van | `tools/safe-force-push.sh` `3`; `blocked`, NINCS push/merge |
| rebase utáni exact-SHA | tiszta rebase új HEAD-et képez | kombinált-HEAD gate és safe push lefut, `blocked` új exact-SHA CI-dispatch kéréssel, NINCS merge |
| PR-identitás | a `gh pr view` base/head/head-SHA mezője eltér | `blocked` a landing-gitműveletek előtt, NINCS push/merge |

**Falszifikációs cellák (kötelezők):**

1. A D2 fail-closed ág lecserélése „ismeretlen útvonal = mechanikus"-ra → az
   „ismeretlen útvonal" és a „vegyes" eset **PIROS** → visszaállítás után zöld.
2. A D3 kapu-lépés kihagyása (rebase után egyből push+merge) → a „piros kapu"
   eset **PIROS** → visszaállítás után zöld.
3. A rebase utáni `blocked` exact-SHA ág kihagyása →
   `test_rebase_requires_a_fresh_exact_sha_ci_before_merging` **PIROS**.
4. A `gh pr view`-alapú PR-kötés kihagyása →
   `test_mismatched_pr_metadata_blocks_before_landing_actions` **PIROS**.

## 5. Tilos zóna — amit ez a kör NEM tesz

- **Nem old fel forráskód-konfliktust.** A szemantikus osztály gépi feloldása
  ebben a körben tilos.
- **Nem vesz át merge-előfeltételt**: review, exact-SHA zöld CI és scope-audit
  változatlan (ADR 0052). A landoló ezek UTÁN fut.
- Nem kapcsol be GitHub natív merge queue-t, nem nyúl branch-védelemhez.
- Nem módosítja a slot-tervezőt (`tools/round-slots.py`) és a
  `tools/round-pipeline.sh`-t — így nem ütközik az E99-R14…R19 körökkel.
- Nem írja a `docs/execution/pipeline-queue.tsv`-t (azt a driver vezeti).
- Fájlok: `docs/adr/**`, `.ai/router.toml`, `.pipeline/**`, Dart források — tilos.

## 6. Definition of Done

1. D1–D5 kész; a `tools/round-land.sh` futtatható és `set -euo pipefail`-t használ.
2. `tools/tests/test_round_land.py` lefedi a §4 nyolc eredeti celláját és a
   két F1/F2 regressziós cellát hermetikus git-fixture-ön (az élő fát nem
   érinti).
3. `python3 -m pytest tools/tests -q` zöld.
4. `tools/round-gate.sh test/tooling/architecture_allowlist_guard_test.dart` zöld.
5. Kör-jelzés `done`.

## 7. Gate

```bash
tools/round-gate.sh test/tooling/architecture_allowlist_guard_test.dart
python3 -m pytest tools/tests -q
```

A gate-lépések külön processzben futnak; a csonkítatlan kimenet a bizonyíték.
A teljes suite + property gate a CI-ban fut (ADR 0053).

## 8. Implementációs sorrend

1. Hermetikus origin + branch fixture és injektált `gh`/gate/signal csonkok.
2. A nyolc mérce-cella RED állapotának rögzítése.
3. `tools/round-land.sh`: argumentumok, merge-zár, rebase és fail-closed
   konfliktus-osztályozás.
4. Kombinált-HEAD gate, `safe-force-push.sh` és merge csak zöld úton.
5. Az orchestrátor-prompt nyers merge-útjának cseréje a landolóra.
6. Falszifikációs próbák, célzott pytest, teljes tooling-suite és round-gate.

## 9. Kockázatok

- A napló-unió elveszíthet vagy duplikálhat szakaszt; a kétoldali egyedi
  markereket és a konfliktusjelölők hiányát külön teszt méri.
- A saját brief azonosítása nem terjedhet ki idegen körre; vegyes és
  ismeretlen konfliktus fail-closed.
- A landoló nem helyettesíti az exact-SHA CI-t vagy a review-t; csak azok
  után hívható, és rebase után a lokális kombinált állapotot újraméri.

## 10. Implementation handoff — a Terra tölti ki

- `tools/round-land.sh`: új, futtatható, `set -euo pipefail` landoló. A
  merge-záron belül fetchel, rebase-el, kizárólag a két append-only naplót
  uniózza és a saját briefnél a friss main-oldalt tartja meg; minden más
  konfliktust H8-cal abortál. A rebase-elt HEAD-en futtatja a megadott vagy
  alapértelmezett kaput, majd a safe-force-push protokollt. A rebase által
  képzett új HEAD-en fail-closed `blocked` jelzéssel új exact-SHA CI-dispatch-t
  kér, és csak egy következő, változatlan igazolt invokációban squash-merge-el.
  Minden landing-gitművelet előtt `gh pr view --json` mezőkből köti a PR-t az
  induló lokális branchhez és HEAD-hez.
- `tools/tests/test_round_land.py`: hermetikus bare-origin fixture és `gh`,
  gate, signal csonkok. A nyolc eredeti cella mellett a rebase utáni exact-SHA
  CI-megállást és az eltérő PR-metaadat fail-closed útját állandó regressziós
  cella méri; a `gh` csonk pozitív és negatív strukturált metaadatot ad.
- `docs/execution/pipeline-orchestrator-prompt.md`: a nyers merge-hívás helyett
  a landoló kötelező hívását írja elő; a mechanikus osztályt a landolóra,
  a szemantikus konfliktust H8-ra vezeti.

Futtatott parancsok és tényleges eredmények:

```text
bash -n tools/round-land.sh
python3 -m pytest tools/tests/test_round_land.py -q
11 passed, 3 subtests passed in 2.50s

tools/round-gate.sh test/tooling/architecture_allowlist_guard_test.dart
format: ZÖLD (1712 fájl, 0 változás)
analyze: ZÖLD (No issues found, 3 elem)
test: ZÖLD (1 passed)
architecture: ZÖLD (12 allowlisted deviation)
secrets: ZÖLD (3044 fájl, 0 finding)

python3 -m pytest tools/tests -q
662 passed, 2 skipped, 574 subtests passed in 320.26s
```

Falszifikációs bizonyíték:

1. A fail-closed ág ideiglenes cseréje „ismeretlen útvonal = mechanikus"
   feloldásra: RED — `3 failed, 6 passed`; a szemantikus tool-, az ismeretlen
   dokumentum- és a vegyes konfliktus tesztje jogtalan sikeres landolást
   mért. Az eredeti abort + H8 ág visszaállítása után GREEN — `9 passed`.
2. A kombinált-HEAD kapu hívásának ideiglenes kihagyása: RED — `2 failed,
   7 passed`; a default kapu eseménye hiányzott és a piros kapu tesztje
   jogtalan sikeres landolást mért. Az eredeti `round-gate.sh` hívás
   visszaállítása után GREEN — `9 passed`.
3. F1/F2 TDD-RED a javítás előtti landolón: a két új regressziós cella
   `2 failed, 9 deselected` eredményt adott, mert a rebase után merge történt,
   és a PR-head eltérése átjutott. A javítás után GREEN — `11 passed, 3
   subtests passed`; az F2-cella külön base-, head-branch- és head-SHA-eltérést
   is fail-closed módon mér.

Eltérés, nem futtatott ellenőrzés, follow-up: nincs. A teljes Flutter-suite,
property gate és exact-SHA Router CI a kör merge-előtti orchestrátori kapuja.

## 11. Review — a Sol tölti ki

Link: `docs/reviews/e99-r20-review.md`
