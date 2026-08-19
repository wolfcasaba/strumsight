# E99-R20 (GOV-14) — Landoló: rebase-őr, konfliktus-osztályozás és kapu a kombinált állapoton

- **Státusz:** READY FOR IMPLEMENTATION (brief 2026-08-18, `main @ 3ceb0787`)
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
- `docs/execution/pipeline-orchestrator-prompt.md:463` a kimondott merge-út:
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
5. `git push --force-with-lease`; elutasítás esetén egyszeri újrafetch +
   ismételt rebase, majd újabb elutasítás → `blocked`, H8-ra hagyva;
6. `gh pr merge <szám> --squash --delete-branch`.

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

### D5 — CI-szűrő

`.github/workflows/router-ci.yml` `paths:` blokkja fedje le a
`tools/round-land.sh` és `tools/tests/test_round_land.py` fájlokat. A szűrő
fedése **nő, sosem szűkül** (mérve: PR #309 piros CI-kapuja).

## 4. Mérce-mátrix (`tools/tests/test_round_land.py`)

Hermetikus git-repókon (fixture: `origin` + branch, ne az élő fát), a `gh`
hívás injektált csonk:

| eset | bemenet | elvárt viselkedés |
|---|---|---|
| tiszta | a branch a friss `main` fölött | rebase kimarad, kapu fut, merge megtörténik |
| mechanikus — napló | `HANDOFF.md` mindkét oldalon új szakasz | unió: MINDKÉT szakasz benne, nincs `<<<<<<<`, merge megtörténik |
| mechanikus — brief | a kör saját briefje ütközik | a `main` oldala marad, merge megtörténik |
| szemantikus | `tools/round-pipeline.sh` ütközik | `rebase --abort`, `blocked`, NINCS merge |
| vegyes | `HANDOFF.md` **és** egy `.dart` forrás is ütközik | szemantikusként kezelve: abort, NINCS merge |
| ismeretlen útvonal | `docs/execution/valami-uj.md` ütközik | szemantikus (fail-closed), NINCS merge |
| piros kapu | rebase rendben, a kapu piros | NINCS push, NINCS merge, `blocked` |
| lease-elutasítás | a `push --force-with-lease` kétszer elutasítva | `blocked`, NINCS merge |

**Falszifikációs cellák (kötelezők):**

1. A D2 fail-closed ág lecserélése „ismeretlen útvonal = mechanikus"-ra → az
   „ismeretlen útvonal" és a „vegyes" eset **PIROS** → visszaállítás után zöld.
2. A D3 kapu-lépés kihagyása (rebase után egyből push+merge) → a „piros kapu"
   eset **PIROS** → visszaállítás után zöld.

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
2. `tools/tests/test_round_land.py` lefedi a §4 mind a nyolc celláját, hermetikus
   git-fixture-ön (az élő fát nem érinti).
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
