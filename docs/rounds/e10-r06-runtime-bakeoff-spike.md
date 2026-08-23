# E10-R06 — Runtime bake-off spike

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ 194b48c4`) — **`hold`: valódi Android eszközt igényel**
- **Típus:** Chapter 11 (Epic 10 — Offline AI), Kör 6
- **Kör-azonosító:** `E10-R06`
- **Branch:** `<motor>/e10-r06-runtime-bakeoff-spike`
- **Előfeltétel:** `E10-R05` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — a spike maga nem köt döntést, az ADR a Kör 7 dolga a bake-off eredményéből.

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "runtime benchmark spike disposable adapter device matrix"` → nincs releváns előzmény (a találatok más domain hibaosztályai) — ez a kör a projekt ELSŐ ilyen jellegű infrastruktúrája, a §5/§9 saját tervezésére támaszkodik.

## 0.0 MIÉRT `hold` — emberi döntés szükséges a dispatch előtt

**Ez a kör a batch-prep pillanatában (2026-08-22) NEM indítható autonóm sessionben.** A jelen fejlesztői/CI környezet:

- **nem rendelkezik Android SDK-val, emulátorral vagy fizikai eszközzel** (a `CLAUDE.md` és `AGENTS.md` is rögzíti: a dev boxon nincs Android SDK, a CI kizárólag `flutter build apk`-t futtat, nem `connectedAndroidTest`-et);
- a kör kimenete VALÓDI eszközön mért TTFT, decode sebesség, memória és 20-run stabilitás — ezt egy LLM-implementer NEM tudja hitelesen előállítani érdemi hardver nélkül, és a kényszerű alternatíva (a számok KITALÁLÁSA) direkt sértené a projekt "no demos — real functionality" szabályát (soha nem szabad fabrikált mért adatot állítani valós mérésként);
- a spike emellett átmenetileg TÖBB, egymással versengő natív runtime-dependency-t igényelhet (`spikes/local_ai_runtime_bakeoff/`), amit a §6.7 SDD-szabály explicit kizár a fő app-ból, de még egy spike-branch build is Android toolchaint kíván.

**Mi oldja fel:** a felhasználó (vagy egy emberi mérnök) fizikai Android eszközökön futtatja le a spike méréseket — akár manuálisan, akár egy jövőben felállított device-farm CI-vel —, majd a nyers eredményeket (`local_ai/benchmark/results/`, `docs/benchmarks/local-ai-runtime-bakeoff.md`) commitolja a kör branchére, VAGY egy explicit human-in-the-loop session felügyeli az implementert, miközben az egy ténylegesen csatlakoztatott/hozzáférhető eszközön dolgozik. Csak EZUTÁN állítható a queue-sor `pending`-re.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "spikes/local_ai_runtime_bakeoff/",
  "docs/benchmarks/local-ai-runtime-bakeoff.md",
  "local_ai/benchmark/results/",
  "docs/rounds/e10-r06-runtime-bakeoff-spike.md",
]
gate_tests = [
  "test/app/config/feature_flags_test.dart",
]
native_gate = false
```

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**Ha ezt a kört mégis dispatch-elnék valódi eszköz nélkül:** az implementer ELSŐ lépése legyen annak ellenőrzése, hogy fut-e csatlakoztatott/elérhető Android eszköz (`adb devices` vagy ekvivalens). Ha nincs, AZONNAL `tools/codex-signal.sh blocked "nincs elérhető Android eszköz a bake-offhoz — emberi/device-farm közreműködés szükséges"` — **fabrikált mérési adat semmilyen körülmények között nem elfogadható**, még "csak becslésként" sem.

## 1. Cél

A jelölt runtime-okat (LiteRT-LM, ExecuTorch, llama.cpp, ONNX Runtime GenAI) tiny és legalább egy reális modelljelölttel kell összehasonlítani reprezentatív, VALÓDI Android eszközökön — spike/eldobható kódként, a fő appba semmilyen production dependency nem kerül.

## 2. Jelenlegi állapot — mért tények

- A Kör 5 (E10-R05) létrehozta a PLACEHOLDER `candidate_models.yaml`-t — ez a kör tölti ki valós méréssel.
- A `spikes/` könyvtár **nem létezik** — ez az első spike a projektben.
- Nincs meglévő device-farm vagy CI-alapú Android instrumentation infrastruktúra ebben a repóban.

## 3. Scope

**Benne van:** eldobható spike adapter minden reálisan buildelhető runtime-hoz · CPU/GPU/NPU backend mérés azonos modellcsaládon · AAR/binary méret, build complexity, minSdk/ABI hatás, load, TTFT, decode, memória, cancel, 20-run stabilitás mérése VALÓDI eszközön · tokenizer/chat-template/streaming/session-reset teszt · JSON/grammar/tool-support felderítés · licenc/maintenance/API-stabilitás dokumentáció.

**NINCS benne (tilos):**

- Több production runtime dependency merge-elése a fő appba (§6.7 SDD) — spike modul vagy külön branch kötelező.
- Fabrikált vagy emulátorból extrapolált "reprezentatív" adat.
- `docs/adr/**` — a döntési ADR a Kör 7 dolga.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `spikes/local_ai_runtime_bakeoff/` | ÚJ — eldobható spike modul(ok) |
| `docs/benchmarks/local-ai-runtime-bakeoff.md` | ÚJ — a mért eredmények és módszertan |
| `local_ai/benchmark/results/` | ÚJ — a Kör 4 sémájának megfelelő nyers JSON eredmények |

**Tilos zóna:** `android/app/**` (a fő app build-je, csak a `spikes/` alatt buildelhet) · `pubspec.yaml` (nincs új production dependency) · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések

### 5.1 Nincs ÚJ kötött döntés — mérési spike, nem production kód

**NEM elfogadható gyengítés:** egyetlen flagship eszközön mért, majd "reprezentatívnak" nyilvánított eredmény — a SDD §21.5 legalább egy budget (~4 GB), egy midrange (~6 GB) és egy flagship (8 GB+) kategóriát kíván.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Legalább két életképes runtime mérve VALÓDI eszközön | `docs/benchmarks/local-ai-runtime-bakeoff.md` |
| A2 | Minden eredmény eszköz-modellhez és OS-verzióhoz köthető | `local_ai/benchmark/results/*.json` |
| A3 | Nincs emulátoron mért adat "reprezentatívként" jelölve | a Kör 4 sémája szerinti `nonRepresentativePerformance` mező |
| A4 | 20 egymást követő generálás crash/OOM nélkül minden mért runtime-on | `local_ai/benchmark/results/*.json` |
| A5 | A licenc/maintenance/API-stabilitás kockázat dokumentált mindegyik jelöltre | `docs/benchmarks/local-ai-runtime-bakeoff.md` |

### 6.1 Falszifikációs próba (docs-only/mérési kör)

Mivel ez a kör mérési adatot termel, nem kódot, a falszifikáció a **reviewer eldobható próbája**: a reviewer kér egy MÁSODIK, független mérési sorozatot ugyanazon az eszközön, és összeveti a szórást — ha a két sorozat median TTFT-je a mért szórás többszörösével eltér, az A1/A2 cella bizonyítatlan marad, és a review CHANGES REQUESTED-et ad.

## 7. Kötelező ellenőrzések

A kör Dart/Flutter kódot nem módosít — a `tools/round-gate.sh` a `gate_tests` regresszió-őrét (a Kör 1-től stabil feature-flag tesztet) futtatja bizonyítékul, hogy a spike nem érintett véletlenül alkalmazáskódot:

```bash
tools/round-gate.sh test/app/config/feature_flags_test.dart
```

A review emellett kötelezően ellenőrzi a mérési eredményt:

```bash
ls local_ai/benchmark/results/*.json   # legalább 2 runtime × legalább 3 eszközkategória
```

## 8. Implementációs sorrend

1. Ellenőrizd az elérhető eszköz(öke)t — nincs eszköz → `blocked`.
2. Spike adapter minden reálisan buildelhető runtime-hoz (`spikes/local_ai_runtime_bakeoff/<runtime>/`).
3. A Kör 5 modelljelöltjeivel vagy tiny fixture modellel mérés minden elérhető eszközön.
4. Az eredmények mentése a Kör 4 sémája szerint.
5. `docs/benchmarks/local-ai-runtime-bakeoff.md` — összefoglaló, licenc/kockázat táblázattal.

## 9. Kockázatok

- **A fabrikált vagy extrapolált adat.** A legsúlyosabb kockázat: egy LLM-implementer, ha nincs valódi eszköze, hajlamos "becsült" számokat írni — ez BLOCKER lenne, nem review-lelet.
- **A spike production dependency-vé szivárgása.** Ha a spike kódja bekerül a fő `pubspec.yaml`-be, azt a §6.7 SDD explicit tiltja.
- **Az egyetlen eszközön mért "reprezentatív" állítás.** Torz döntést eredményezne a Kör 7 ADR-jében.

## 10. Implementation handoff — az implementer tölti ki (VALÓS eszköz-hozzáférés után)

## 11. Review — a Claude tölti ki
