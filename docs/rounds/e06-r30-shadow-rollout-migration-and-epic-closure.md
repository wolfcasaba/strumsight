# E06-R30 — Shadow rollout, migráció és Epic lezárás (ZÁRÓ KÖR)

- **Státusz:** PREPARED (előre megírva 2026-08-07, kód olvasva: main @ `a6e6f3d`)
- **SDD-kör:** [`docs/sdd/07-epic-06-audio-analysis-2.md`](../sdd/07-epic-06-audio-analysis-2.md) Kör 30; §30.1–30.4, §33
- **Branch:** `codex/e06-r30-shadow-rollout-migration-and-epic-closure`
- **Előfeltétel:** **MIND (E06-R01 … E06-R29 merge)**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/audio_analysis/application/shadow_analysis_runner.dart",
  "lib/features/audio_analysis/domain/rollout/analysis_rollout_stage.dart",
  "lib/features/audio_analysis/data/shadow/shadow_diff_report.dart",
  "lib/features/audio_analysis/public.dart",
  "lib/app/config/feature_flags.dart",
  "test/features/audio_analysis/application/shadow_analysis_runner_test.dart",
  "test/features/audio_analysis/data/shadow_diff_report_test.dart",
  "test/features/audio_analysis/data/full_migration_test.dart",
  "test/features/audio_analysis/data/rollback_test.dart",
  "test/app/analysis_rollout_flags_test.dart",
  "README.md",
  "HANDOFF.md",
  "docs/sdd/00-index.md",
  "docs/sdd/epic-06-completion-report.md",
  "docs/manual-testing/analysis-eval-matrix.md",
  "docs/execution/06-requirements-traceability-matrix.md",
  "docs/rounds/e06-r30-shadow-rollout-migration-and-epic-closure.md",
]
gate_tests = [
  "test/features/audio_analysis",
  "test/app",
  "test/features/analyze",
  "test/features/library",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** friss `origin/main` + **mind a 29** előző kör
> merge. Ellenőrizd a `docs/execution/06-requirements-traceability-matrix.md`
> **mai** formátumát és az `epic-0X-completion-report.md` fájlok szerkezetét
> (az Epic 1–4 zárójelentései a minta). **H-GATEGUARD:** a `.github/workflows/**`
> és a `tool/ci/**` nem módosítható — a hátralévő CI-munkát a completion
> report **nevesíti** `GOV-xx` körként. A **V1 eltávolítása NEM ennek a
> körnek a feladata** (SDD Kör 30 §7). PREPARED→PLANNING, brief commit előbb.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED.** Új ADR nincs — a kör a meglévő ADR 0200–0211-et **frissíti**
(állapot/következmény szakaszok), nem hoz újat. **Záró-kör waiver:** az
Epic 4 (E04-R24) és az Epic 5 (E05-R30) precedense szerint ez a kör **nem**
kap ADR 0087 §7 szerinti kézi indítást; a rollout/flag/ADR kérdések a
briefben **pre-decidáltak**. Változatlan marad az automata független
review (ADR 0055) és az exact-SHA zöld CI.

## 1. Cél

A V2 **biztonságos** bevezetése: shadow mód, rollout-lépcsők, teljes legacy
migrációs teszt, bizonyított rollback, és az Epic **lezárása** —
a V1 kivezetése **nélkül**.

## 2. Jelenlegi állapot (mért, `a6e6f3d` + az R01–R29 kimenete)

- A V1 Analyze **változatlanul** a shipping út (ADR 0205); a V2 minden
  képessége flag mögött, default OFF.
- Az Epic 6 flagjei (a batch tervezett listája; a pre-flight méri a
  ténylegeset): `audioAnalysisV2Enabled`, `analysisBeatGridEnabled`,
  `analysisPitchEnabled` (R02), `analysisPreprocessingExperimentalEnabled`
  (R08), `analysisExperimentalFusionEnabled` (R11),
  `analysisTechniqueProxiesEnabled` (R18), `analysisComparisonEnabled` (R25),
  `analysisPracticeIntegrationEnabled` + `analysisTutorIntegrationEnabled`
  (R26) — **kilenc** flag, mind OFF.
- Az R21 migrátora a legacy Library-t V2 dokumentumokká alakítja, és a
  **legacy kulcsot nem törli**.
- Az `analysis-eval-matrix.md` PENDING sorai gyűjtik a valós eszközös
  bizonyítékot.

## 3. Scope

**Benne:** `AnalysisRolloutStage` (V1 default → V2 shadow (Lab) → V2 opt-in →
V2 default); `ShadowAnalysisRunner` (a V2 a V1 **mellett** fut Lab módban,
a felhasználói eredményt **nem** befolyásolva); `ShadowDiffReport`
(event count, chord szegmensek, BPM, hossz, futásidő, hibák);
**teljes** legacy migrációs teszt; **rollback** teszt; a dokumentáció
frissítése (README, HANDOFF, SDD index, ADR-státuszok);
`docs/sdd/epic-06-completion-report.md`.

**Kívül — TILOS:** a V1 **eltávolítása**, a legacy kulcs törlése, bármely
workflow/CI fájl, új képesség, DSP-változtatás.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../application/shadow_analysis_runner.dart` | ÚJ | shadow futtatás |
| `.../domain/rollout/analysis_rollout_stage.dart` | ÚJ | rollout lépcsők |
| `.../data/shadow/shadow_diff_report.dart` | ÚJ | diff-riport |
| `.../public.dart` | meglévő | export |
| `lib/app/config/feature_flags.dart` | meglévő | rollout-lépcső leképezés |
| `test/**` | ÚJ | shadow + migráció + rollback + flag |
| `README.md`, `HANDOFF.md` | meglévő | dokumentáció |
| `docs/sdd/00-index.md` | meglévő | Chapter 7 státusz |
| `docs/sdd/epic-06-completion-report.md` | ÚJ | zárójelentés |
| `docs/manual-testing/analysis-eval-matrix.md` | meglévő | nyitott PENDING sorok |
| `docs/execution/06-requirements-traceability-matrix.md` | meglévő | nyomon követés |

**Tilos zóna:** `.github/**`, `tool/ci/**`, `tools/round-gate.sh`,
`lib/features/analyze/**` (a V1 **marad**), `lib/features/live/**`,
`assets/**`, `docs/adr/*.md` **új** fájl. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **A V1 marad a shipping út** (ADR 0205, SDD Kör 30 §7): a kör
   **nem** kapcsolja a V2-t alapértelmezetté, és **nem** távolítja el a V1-et.
   **NEM elfogadható:** bármely flag `true`-ra állítása production
   környezetben.
2. **A shadow mód nem befolyásolja a felhasználói eredményt** (SDD §30.3):
   a V1 eredménye **bitre** ugyanaz shadow ON és OFF mellett; a V2 kimenete
   kizárólag diagnosztika. **NEM elfogadható:** a shadow futás hibája
   megbuktatja a V1 elemzést.
3. **A shadow csak Lab módban fut**, és a többletköltség **mért**
   (a diff-riport tartalmazza a V1 és V2 futásidejét).
4. **Rollback bizonyított:** a flagek visszakapcsolása után a Library
   **mindkét** verziót olvassa, és egyetlen V2 dokumentum sem sérül.
   **NEM elfogadható:** irreverzibilis migráció backup nélkül.
5. **H-GATEGUARD határ:** a CI-oldali evaluation/regressziós lépés (R29)
   bekötése **nem** ennek a körnek a dolga; a completion report
   **nevesíti** a hátralévő munkát `GOV-xx` körként, felelőssel.
   **NEM elfogadható:** workflow-fájl szerkesztése.
6. **A valós eszközös elfogadás merge UTÁNI termékelfogadás** (CLAUDE.md
   HORIZON): az SDD Kör 30 „Valódi eszköz ellenőrzés" 14 pontja
   **PENDING sorként** kerül az eval-mátrixba, **nem** merge-kapuként.
   **NEM elfogadható:** teljesíthetetlen acceptance-pont, ami a láncot
   HALT-ra viszi.
7. **A completion report őszinte:** felsorolja a **nem** teljesült DoD-pontokat
   és a nyitott follow-upokat (Song/Tutor fogyasztás, waveform preview,
   valódi kalibráció, CI-kapu, V1 kivezetés). **NEM elfogadható:**
   „minden kész" állítás mérés nélkül.

### 5.1 Nyitott döntések — előre rögzített feloldással

```yaml
open_decisions:
  - id: OD-01
    question: A rollout melyik lépcsőn álljon meg ebben a körben?
    blocking: true
    resolution_policy: use_default
    default: >-
      "V2 shadow (Lab)" — azaz a shadow runner elkészül és Lab módban
      futtatható, de MINDEN flag default OFF marad minden környezetben.
      Az opt-in és a default-on lépcső külön, ember által jóváhagyott
      döntés (a completion report nevesíti).
  - id: OD-02
    question: Mi legyen, ha egy DoD-pont bizonyíthatatlan ezen a boxon?
    blocking: true
    resolution_policy: use_default
    default: >-
      a completion reportban "NEM BIZONYÍTOTT (ok: …)" jelöléssel + PENDING
      sor az eval-mátrixban, felelőssel és mérendő számmal. NEM "kész".
  - id: OD-03
    question: A `docs/sdd/00-index.md` Chapter 7 sora mit írjon?
    blocking: false
    resolution_policy: use_default
    default: >-
      "30 — implementation evidence recorded; rollout stays at shadow,
      release blockers remain" (az Epic 3 sorának mintájára), NEM
      "lezárva", amíg a valós eszközös elfogadás és a CI-kapu nyitott.
```

## 6. Acceptance criteria

- [ ] **Shadow-invariancia:** ugyanarra a bemenetre a V1 eredménye
      **bitre azonos** shadow **ON** és **OFF** mellett — a kilenc R09-fixture
      mindegyikére.
- [ ] **Shadow-hibaizoláció:** ha a V2 pipeline **dob** vagy **cancel**-t kap,
      a V1 eredmény **változatlanul** elkészül, és a diff-riport
      `v2Failed: true` jelölést kap. Két cella (dobás / cancel).
- [ ] **Shadow-kapu mátrix — négy cella:** (Lab OFF, flag OFF),
      (Lab OFF, flag ON), (Lab ON, flag OFF), (Lab ON, flag ON) — a V2 futás
      **kizárólag** az utolsóban indul (hívásszámláló).
- [ ] **Diff-riport tartalma:** event count, chord szegmensszám, BPM, hossz,
      V1 és V2 futásidő, hibajelzés — mind a hat mező jelen van, és a riport
      **determinisztikus** (időbélyeg nélkül).
- [ ] **Teljes migrációs teszt:** **50** legacy sessionből álló store →
      mind az 50 V2 dokumentum, `id`/`createdAt`/`customTitle` megőrizve,
      a legacy kulcs **bitre változatlan**, és a migráció **kétszer**
      futtatva ugyanazt adja.
- [ ] **Rollback-teszt:** migráció után **minden** flag OFF → a Library V1
      útja **változatlanul** működik (a `test/features/library` zöld), a V2
      dokumentumok a lemezen **sértetlenek**, és a flagek visszakapcsolásával
      újra olvashatók.
- [ ] **Flag-őr:** mind a **kilenc** Epic 6 flag `false` **minden**
      környezetben (dev/lab/staging/production — a mai enum tényleges
      értékeire), és egyikhez sincs dart-define override.
- [ ] **V1 regressziómentesség:** `git diff --stat` nem tartalmaz
      `lib/features/analyze/**`, `lib/features/live/**` vagy
      `lib/features/library/**` útvonalat; a `test/features/analyze` és
      `test/features/library` **átírás nélkül** zöld.
- [ ] **Completion report:** végigmegy az SDD §33 **összes** DoD-pontján, és
      mindegyikhez ad: **teljesült / NEM BIZONYÍTOTT (ok) / follow-up
      (kör-javaslat)**. A „NEM BIZONYÍTOTT" sorokhoz eval-mátrix PENDING sor
      tartozik, felelőssel.
- [ ] **A hátralévő CI-munka nevesítve:** a report külön szakaszban rögzíti a
      `GOV-xx` körre maradó, H-GATEGUARD miatt itt nem végezhető munkát
      (R29 evaluation-gate CI-lépés), és a **pontos** fájlokat, amiket
      érintene.
- [ ] **Valós eszközös lista:** az SDD Kör 30 **mind a 14** eszközös
      ellenőrzési pontja (record, cancel, background, import, 30 s klip,
      hosszabb klip, overview, timeline zoom, save/reopen, compare,
      Practice action, Tutor action, offline mód, audio deletion) **PENDING**
      sorként szerepel az eval-mátrixban, felelőssel.
- [ ] **Dokumentáció:** README + HANDOFF + `docs/sdd/00-index.md` Chapter 7
      sora frissítve az OD-03 szerint; a traceability mátrix az Epic 6
      köreire kitöltve.
- [ ] **ADR-státuszok:** a 0200–0211 ADR-ek „Állapot"/"Következmény"
      szakasza frissítve a **mért** kimenettel (különösen 0201 kalibráció,
      0205 rollout, 0207 fusion, 0209 storage).

> **Küszöb-konvenció:** minden numerikus küszöbhöz a mátrix **három** cellát
> ad — szigorúan **alatta**, pontosan **rajta**, szigorúan **fölötte** —, és a
> cellák értékei `python3 -c`-vel kiszámoltak, nem idealizált rácsból becsültek
> ([`docs/LESSONS.md`](../LESSONS.md) L13).

### 6.1 Mérce-mátrix — melyik hibás implementációt fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A shadow futás megváltoztatja a V1 eredményt | a shadow-invariancia kilenc fixture-cellája |
| A V2 hibája megbuktatja a V1-et | a shadow-hibaizoláció dobás/cancel cellái |
| A shadow flag nélkül is fut | a shadow-kapu mátrix első három cellája |
| Bármely flag `true` production-ben | a flag-őr cella |
| A migráció törli a legacy kulcsot | a „legacy kulcs bitre változatlan" cella |
| A migráció duplikál 50 sessionön | a kétszeri futtatás cella |
| A rollback után a V1 út törik | a `test/features/library` zöldje |
| A report „minden kész"-t állít | a DoD-pontonkénti háromértékű jelölés cella (a NEM BIZONYÍTOTT sorok hiánya) |
| A 14 eszközös pont merge-kapuként szerepel | a PENDING-sor cella (a lánc HALT-ra menne) |
| Workflow-fájl módosul | a `protect_factory_files.py` hook + a §4 tilos zóna |
| **Valódi-sértés próba (§10):** a shadow-ág ideiglenes bekapcsolása flag OFF mellett → a shadow-kapu mátrix cellája **PIROS** → visszaállítás |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/audio_analysis test/app test/features/analyze test/features/library
```

Külön processzek, nincs `&&`/pipe/`tail`. A **teljes** suite + randomizált
property gate + APK a CI-ban fut (ADR 0053), exact-SHA dispatch az
orchestrátortól; a merge-kapu változatlan.

## 8. Implementációs sorrend

1. `analysis_rollout_stage.dart` + a flag-leképezés (mind OFF).
2. RED: shadow-invariancia, hibaizoláció, kapu-mátrix.
3. `shadow_diff_report.dart` + `shadow_analysis_runner.dart`.
4. Teljes migrációs és rollback teszt (50 session).
5. `docs/sdd/epic-06-completion-report.md` (DoD-pontonként).
6. README / HANDOFF / SDD index / traceability / ADR-státuszok.
7. Eval-mátrix: a 14 eszközös pont + a nyitott PENDING sorok.
8. Gate.

## 9. Kockázatok

- **A záró kör hajlamos „mindent lezárni"** — a §5.7 és az OD-02 kimondja:
  a nem bizonyított pont **nem** kész; az őszinte report a kör értéke.
- **A shadow futás megduplázza a költséget** — kizárólag Lab módban fut, és
  a diff-riport méri; a §10-ben a mért többletet rögzíteni kell.
- **A 29 kör fájljai közben elmozdulhattak** — a pre-flight a flaglistát és a
  fájlneveket **méri**, nem a briefből veszi.
- **A V1 kivezetése csábító** — külön, ember által jóváhagyott döntés, a
  report nevesíti.

**STOP:** flag bekapcsolása, V1 eltávolítása, workflow-szerkesztés vagy
bizonyítatlan „kész" állítás helyett `stopped` + brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e06-r30-shadow-rollout-migration-and-epic-closure-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
**Kötelező:** `security-reviewer` (risk = high, migráció + adatvédelem + rollout).
