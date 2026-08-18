# E99-R19 (GOV-13) — Lánc-higiénia: main-szinkron, egyetlen záró commit, őszinte kockázati besorolás

- **Státusz:** READY FOR IMPLEMENTATION (brief 2026-08-18, `main @ 52324cb3`)
- **Típus:** **governance-kör**
- **Kör-azonosító:** `E99-R19`. Emberi neve **GOV-13**.
- **Előfeltétel:** `E99-R15` merge-elve (`tools/round-pipeline.sh`), `E99-R16` merge-elve (`tools/brief-lint.py`)
- **Brief szerzője:** Claude (Opus 5, orchesztrátor) · **ADR:** [`0307`](../adr/0307-pipeline-throughput-program-v2.md) **§6**

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "tools/round-pipeline.sh",
  "tools/brief-lint.py",
  "tools/tests/test_chain_hygiene.py",
  "tools/tests/test_brief_risk_justification.py",
  "docs/execution/pipeline-orchestrator-prompt.md",
  "docs/rounds/e99-r19-gov-13-chain-hygiene.md",
]
gate_tests = [
  "test/tooling/architecture_allowlist_guard_test.dart",
]
native_gate = false
```

> **Kockázat = high, indoklás:** a diff a lánc indulási kapuját (main-szinkron)
> és a záró rituálét (sor-státusz commit) érinti — egy hibás ág vagy némán
> felülírt lokális commitot, vagy elveszett `done` státuszt okozna. A
> `gate_tests` cella fa-egészség őr; a tényleges mérce a `pytest tools/tests`
> és a Router CI (§7).

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. **STOP-protokoll:** listán kívüli fájl →
`stopped` + brief-revízió; az `allowed_paths` tágítása TILOS.

## 1. Cél — három mért, kicsi, ismétlődő veszteség

1. **Main-szinkron.** 2026-08-11 … 08-18 között **9** firing maradt ki azzal,
   hogy „a lokális main eltér az origin/main-től — előbb rendezd (fetch +
   ff-merge)"; egyetlen epizód (08-18 17:55–18:13) **négy** egymást követő
   firinget ejtett ki. A munkafa MINDVÉGIG tiszta volt: a lánc olyasmire várt,
   amit maga is elvégezhetett volna.
2. **Két záró push körönként.** A kör végén `docs(handoff…)` és
   `chore(pipeline)` külön commitban, külön pushban megy → **két** Router CI
   futás (mérve 4 perc 45 mp/futás), és minden extra futás egy potenciális
   „fut egy workflow" blokkolás.
3. **A kockázati besorolás nem szelektál.** A 75 nyitott briefből **68** a
   `risk = "high"` — így a magas-kockázatú ág (security-review, szigorúbb
   escalation) gyakorlatilag minden körre fut, a jelzés pedig elveszti az
   értelmét.

## 2. Jelenlegi állapot — mérve a kódban

- `tools/round-pipeline.sh`: a main-eltérés őre `die`-jal áll meg; nem
  különbözteti meg a LEMARADÁST (fast-forwardolható) a valódi DIVERGENCIÁTÓL
  (lokális, origin-en nem létező commit).
- `tools/round-pipeline.sh:1919`: a sor-státusz saját commitot és pushot kap
  („hogy a kör diffjét ne szennyezze") — a merge UTÁN, tehát a kör diffje
  ekkor már lezárt.
- `tools/brief-lint.py`: a `risk` mezőt nem vizsgálja.

## 3. Feladatok

### D1 — Main-szinkron tiszta fán

- Ha a munkafa **tiszta**, a `main` ágon áll, és az `origin/main` szigorúan
  ELŐRE van (a lokális HEAD az origin őse), a driver `git merge --ff-only`-val
  szinkronizál, naplózza (`main-szinkron: <régi> → <új> (ff-merge)`), és
  FOLYTATJA a firinget.
- **Valódi divergencia** (van lokális commit, ami nincs az originen) → a mai
  viselkedés: megáll, naplóz, értesít. Ezen a ponton emberi döntés kell.
- Piszkos munkafa → változatlanul megáll (ADR 0175 §2 határa).

### D2 — Egyetlen záró commit

- A záró rituálé (`docs/execution/pipeline-orchestrator-prompt.md` §5) úgy
  módosul, hogy az orchesztrátor a sor-fájl `pending → done` átírását
  **ugyanabba a `docs(handoff…)` commitba** teszi, mint a HANDOFF/RTM/LESSONS
  frissítést — egy commit, egy push, egy CI.
- A driver `chore(pipeline)` ága **fail-safe-ként megmarad**: ha a státusz a
  merge után még `pending`, változatlanul commitol. Ha már `done`, nem
  keletkezik üres commit. A `done` státusz elvesztése így akkor is kizárt, ha
  az orchesztrátor kihagyja a lépést.

### D3 — A `risk = "high"` indoklást kér (`brief-lint --level strict`)

- Új `strict` lelet (`S7`): `risk = "high"`, de a brief sem a
  `.ai/router.toml` `high_risk_path_fragments` valamelyikét nem érinti az
  `allowed_paths`-ban, sem nem tartalmaz `**Kockázat = high, indoklás:**`
  kezdetű mondatot → lelet.
- **`base` szinten NEM lelet** (a CI-kapu nem szigorodik): a cél a jövőbeli
  briefek fegyelme, nem a 68 meglévő brief pirosra állítása.

## 4. Mérce-mátrix

| eset | bemenet | elvárt |
|---|---|---|
| main **lemaradt**, fa tiszta | HEAD az origin/main őse | ff-merge, a firing FOLYTATÓDIK |
| main **azonos** | HEAD == origin/main | nincs művelet, a firing folytatódik |
| main **divergál**, fa tiszta | lokális commit nincs az originen | megáll + ntfy (mai viselkedés) |
| main lemaradt, fa **piszkos** | tracked változás a fán | megáll (mai viselkedés) |
| záró commit: státusz már `done` | a sor-fájl frissítve | NINCS `chore(pipeline)` commit |
| záró commit: státusz `pending` | az orchesztrátor kihagyta | `chore(pipeline)` commit születik (fail-safe) |
| `risk=high`, indoklás nélkül, nem-kockázatos útvonalak | fixtúra-brief | S7 **strict** lelet, `base` tiszta |
| `risk=high`, `**Kockázat = high, indoklás:**` sorral | fixtúra-brief | nincs lelet |

**Falszifikációs cella (kötelező):** a D1 „szigorúan előre van" ellenőrzés
lecserélése puszta „eltér"-re → a „main divergál" eset **PIROS** (a lánc némán
felülírná a lokális commitot) → visszaállítás után zöld. Második falszifikáció:
a D2 fail-safe ágának kiszedése → a „státusz `pending`" eset **PIROS**.

## 5. Tilos zóna

- `docs/adr/**`, `.ai/router.toml`, `docs/execution/pipeline-queue.tsv`,
  `.pipeline/**`, minden Dart forrás.
- A `git reset --hard`, a `git stash` és bármilyen force-push a driverben
  **tilos** — a D1 kizárólag `merge --ff-only`-t használhat (a megosztott
  munkafa miatt: `docs/LESSONS.md`, stash-veszély).
- A `base` lint-szint NEM bővül.

## 6. Definition of Done

1. D1–D3 kész; a §4 mind a nyolc cellája tesztelt
   (`tools/tests/test_chain_hygiene.py`, `tools/tests/test_brief_risk_justification.py`).
2. `python3 tools/brief-lint.py --open --level base` továbbra is nulla lelet.
3. `python3 -m pytest tools/tests -q` zöld.
4. `tools/round-gate.sh test/tooling/architecture_allowlist_guard_test.dart` zöld.
5. Kör-jelzés `done`.

## 7. Gate

```bash
tools/round-gate.sh test/tooling/architecture_allowlist_guard_test.dart
python3 -m pytest tools/tests -q
python3 tools/brief-lint.py --open --level base
```

A gate-lépések külön processzben futnak, a kimenet csonkítatlan. A teljes suite
+ property gate a CI-ban fut (ADR 0053).
