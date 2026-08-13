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

**PREPARED.** Új ADR nincs — a kör a meglévő Epic 6 ADR-eket **frissíti**
(állapot/következmény szakaszok), nem hoz újat — a valós készlet 0215–0249,
lásd R1 lent. **Záró-kör waiver:** az Epic 4 (E04-R24) és az Epic 5
(E05-R30) precedense szerint ez a kör **nem** kap ADR 0087 §7 szerinti kézi
indítást; a rollout/flag/ADR kérdések a briefben **pre-decidáltak**.
Változatlan marad az automata független review (ADR 0055) és az exact-SHA
zöld CI.

### R1 — ADR-tartomány javítva: 0200–0211 nem létezik, a valós készlet 0215–0249

**MÉRVE (orchestrátor pre-flight, 2026-08-13, `main @ 8341f600`):** a brief
2026-08-07-i batch-fejléce sorszám-extrapolációval írta a „0200–0211"
tartományt (ugyanaz a mintázat, mint E06-R01/E06-R28 korábbi mért driftje,
`docs/LESSONS.md` L194/L267) — `ls docs/adr/` **nulla** találatot ad erre a
tartományra. A `reserve-adr` foglaló-lánc a valós Epic 6 ADR-készletet
**0215–0221, 0224–0241, 0243, 0246–0249**-ként adta (29 ADR — E06-R01 hat
kötött ADR-t foglalt egyszerre, a többi kör egyet-egyet, E06-R26 nullát). A
§6 „ADR-státuszok" acceptance criterion **javított** olvasata:

| Brief eredeti hivatkozása | Valós ADR | Cím | Kör |
|---|---|---|---|
| „0201 kalibráció" | **0216** | analysis-confidence-calibration-and-abstention | E06-R01 |
| „0205 rollout" | **0220** | audio-analysis-v2-parallel-rollout-boundary | E06-R01 |
| „0207 fusion" | **0229** | analysis-chord-decoder-fusion-strategy | E06-R11 |
| „0209 storage" | **0239** | analysis-document-storage | E06-R21 |

A **teljes** frissítendő készlet: 0215–0220 (E06-R01, hat kötött ADR), 0221
(E06-R03), 0224 (E06-R07), 0225 (E06-R08), 0226 (E06-R09), 0228 (E06-R10),
0229 (E06-R11), 0230 (E06-R12), 0231 (E06-R13), 0232 (E06-R14), 0233
(E06-R15), 0234 (E06-R16), 0235 (E06-R17), 0236 (E06-R18), 0237 (E06-R19),
0238 (E06-R20), 0239 (E06-R21), 0240 (E06-R22), 0241 (E06-R23), 0243
(E06-R24), 0246 (E06-R25), 0247 (E06-R27), 0248 (E06-R28), 0249 (E06-R29).
E06-R26-nak nincs saját ADR-je (0176/0132/0141/0202 végrehajtása — MÁS epic
ADR-jei, ezt a kört NEM ez a round frissíti).

**Szekció-konvenció javítva:** egyik ADR-nek sincs „Állapot"/„Következmény"
(egyes szám) című szakasza — a valós minta egy `- **Státusz:** …`
fejléc-sor (mindegyik már „Elfogadva"-ra áll) + egy `## Következmények`
(többes szám) szakasz. A frissítés: a `## Következmények` szakasz
kiegészítése egy mért záró bekezdéssel ott, ahol a szöveg még jövő időben
ír egy azóta lezárult körről (pl. 0216 „a
`ConfidenceCalibrationCapabilityResolver`-t egy jövőbeli E06-R19
implementálja" → E06-R19 **megtörtént**, és
`docs/manual-testing/analysis-eval-matrix.md` szerint a kalibráció ma is
`identity.v1`-en áll, valódi dataset nélkül — ezt kell rögzíteni). Ahol az
ADR már mérve/múlt időben ír (pl. 0220, 0239, 0229), elég egy rövid „R30-nál
is érvényes, változatlan" megerősítés dátummal — **nem kell mind a 29 ADR-t
tartalmilag átírni**, csak azokat, ahol a szöveg egy azóta megtörtént/mért
eseményt jövő időben ír le.

### R2 — „§30.1–30.4" és „Kör 30 / §33" két KÜLÖNBÖZŐ SDD-szakasz

A brief fejléce („Kör 30; §30.1–30.4, §33") két, egymástól független
szakaszt fűz össze: a `docs/sdd/07-epic-06-audio-analysis-2.md` **`# 30.
Feature flagek és rollout`** fejezete (2579. sor, alszakaszai `30.1`–`30.4`,
2581–2626. sor) egy **általános, epic-szintű** rollout-tervezési fejezet —
NEM ennek a körnek a tartalmi specifikációja. A **kör saját tartalma** a
külön **`# Kör 30 — Shadow rollout, migráció és Epic lezárás`** szakasz
(4229–4320. sor: Cél/Feladatok/Kötelező ellenőrzések/Valódi eszköz
ellenőrzés/Elfogadási feltételek/Javasolt commit), a DoD-lista pedig a
**`# 33. Epic 6 végső Definition of Done`** szakaszban él (4322–4430,
**74 `- [ ]` tétel 11 `##` kategóriában**, NEM táblázat). Mindhárom releváns,
csak nem egymás alszakaszai — a `30.1 Rollout szintek` (2593. sor, hét
lépcső: unit/fixture teszt → developer-only → Lab mode → internal dogfood →
opt-in beta → default-on → legacy Analyze eltávolítása) hasznos bemenet az
`AnalysisRolloutStage` enum tervezéséhez, de a kör konkrét elfogadási
feltétele a „Kör 30" szakasz + a §6 (ez a fájl) + a §33 DoD.

A „Valódi eszköz ellenőrzés" **14 pontja mérve egyezik** a §6 utolsó
acceptance-cellájával (record, cancel, background, import, 30s klip,
hosszabb klip, overview, timeline zoom, save/reopen, compare, Practice
action, Tutor action, offline mode, audio deletion) — nincs revízió, csak
megerősítés.

### R3 — Completion report: nincs „teljesült/NEM BIZONYÍTOTT/follow-up" precedens — az Epic 1/4 checkbox-mintát kövesd

**MÉRVE:** a meglévő öt completion report (`docs/sdd/epic-0[1-5]-completion-report.md`)
egyikében sincs „teljesült" vagy „NEM BIZONYÍTOTT" szó szerinti string — a §6
„Completion report" acceptance criterion ezt a konvenciót **új**, nem
meglévő mintaként írja elő. A brief saját fejléce viszont explicit kimondja:
„az Epic 1–4 zárójelentései a minta" — kövesd a ténylegesen meglévő
Epic 1/Epic 4 mintát a kitalált három-állapotú prózajelölés helyett:

```
- [x] **<SDD DoD-tétel szó szerint>.** <bizonyíték: fájl:sor/kör/mérés>.
- [ ] **<SDD DoD-tétel szó szerint>.** <ok: miért nem bizonyított/PENDING sor hivatkozás>.
```

(Epic 4 minta: `docs/sdd/epic-04-completion-report.md:11-262`, `##`
alszakaszok az SDD DoD-kategóriák szerint — a §33 saját 11 kategóriája
pontosan erre a mintára illeszkedik —, a végén egy külön `## Nyitott
tételek` táblázat `| Tétel | Felelősség | Határidő |` oszlopokkal; Epic 1
minta: `docs/sdd/epic-01-completion-report.md:165-267`, záró összegző sorral
„N/M tétel evidenciával kipipálva"). A §6 „teljesült / NEM BIZONYÍTOTT (ok) /
follow-up" hármas felsorolása **tartalmilag** helyes elvárás (minden tételt
kategorizálni kell), csak a **formátumát** kell a fenti, már bevett
checkbox+indoklás mintára fordítani — a `[ ]` sor indoklása maga jelöli, hogy
NEM BIZONYÍTOTT (mérési okkal) vagy follow-up (kör-javaslattal). (Epic 5
riportja **nem** ez a minta — angol prózariport, a brief kifejezetten az
1–4 köröket nevezi meg forrásként.)

### R4 — Eval-mátrix: a 14 új sor azonosítója EVAL-28…EVAL-41, az ELSŐ táblázat-blokkba

`docs/manual-testing/analysis-eval-matrix.md` ma **27** sort tartalmaz
(`EVAL-01`…`EVAL-27`, két táblázat-blokkban; a második blokk, `EVAL-22`–`26`,
hiányzó fejléc-sorral rendelkezik — meglévő, ezen körön KÍVÜLI hiba, ne
javítsd, ne bővítsd azt a blokkot). A 14 új, „Valódi eszközös lista"
acceptance criterion által kért sor kapja a **EVAL-28…EVAL-41** azonosítót,
az ELSŐ (helyesen fejlécelt, 7–30. sor) blokkba fűzve, a meglévő oszlopséma
szerint (`| ID | Állapot | Felelős | Reprodukálható bemenet | Mérendő szám |`).

### R5 — A kilenc „R09-fixture" privát teszt-adat, nem megosztott fixture-könyvtár

A §6 „Shadow-invariancia" pont „a kilenc R09-fixture mindegyikére" szövege
egy **importálható** fixture-készletet sugall — a valóság: a kilenc eset
(silence, two chords, four chords C·G·Am·F, ring-out overlap, single strum,
known BPM strum sequence, throwing refiner fallback, empty input, sample
rate zero) egy **fájl-privát** `_fixtures` lista
(`test/features/audio_analysis/engine/clip_analyzer_parity_test.dart:47-87`),
máshonnan nem importálható. Az új shadow-teszt ugyanezt a kilenc forgatókönyvet
**újra felépíti** a már meglévő `test/support/synth.dart` helperekkel
(`chordSignal`/`strumSignal`/`strumPattern`/`overlappingStrums`) — ugyanazok
a segédfüggvények, amiket az R09-teszt is importál. Nem hiba, csak pontosítás:
„a kilenc R09-fixture" = „az R09 kilenc forgatókönyve, újraépítve", nem egy
megosztott adatfájl.

### R6 — A V2 oldal: melyik hívást fogja a shadow runner meghívni, és mit jelent, hogy `analysisV2RunnerProvider` fail-closed

**V1 hívás** (a shadow runner ezt hívja meg, VÁLTOZATLANUL — az
`allowed_paths` ki is zárja a módosítását): a top-level
`runClipAnalysis`/`computeClipAnalysis`
(`lib/features/analyze/providers/analyze_providers.dart:41-79,108-121`) —
NEM az `AnalyzeController`, NEM a screen.

**V2 hívás:** a szerződés `AnalysisRunner.start(AnalysisDocument) →
AnalysisRunHandle` (`.result` egy `Future<AnalysisRunResult>`,
`domain/analysis_document.dart` + `application/analysis_isolate_runner.dart`).
**MÉRVE: `analysisV2RunnerProvider` ma feltétel nélkül `StateError`-t dob**
(`application/analysis_providers.dart:210-218`, ADR 0240 Döntés 4 szándékos
fail-closed csonkja — nincs összeszerelt V2 DSP-lánc). Ez a fájl **nincs**
az `allowed_paths`-on, tehát ez a kör **nem** teheti nem-dobóvá. Ebből
KÖVETKEZIK a helyes tervezési döntés (a §5 Döntés 2/3 és a §6
„Shadow-hibaizoláció"/„Diff-riport" pontok így teljesíthetők):

1. `ShadowAnalysisRunner` az `AnalysisRunner`-t (a V2 szerződést) **konstruktor-
   paraméterként** kapja — NEM Riverpod-providerből olvassa saját maga
   (a `buildTechniqueProxyReport` mintáját követve,
   `lib/features/audio_analysis/engine/metrics/technique_proxies.dart:139-154`,
   amely a flag+Lab két tengelyét is független bool-paraméterként kapja, nem
   beágyazott olvasással).
2. A **teszteket** (`shadow_analysis_runner_test.dart`) egy test-double
   `AnalysisRunner`-rel írd (sikeres/dobó/cancel-elő változat mindhárom
   cellához) — a valós `analysisV2RunnerProvider` bekötése (és ezzel egy
   ÉLES V1↔V2 diff) egy JÖVŐBELI, pipeline-összeszerelő kör dolga (lásd a
   HANDOFF.md §3 „A valódi, több-stage V2 DSP pipeline összeszerelése MÉG
   NEM ÜTEMEZETT kör" tételét).
3. Ez a kör — az Epic 6 minden korábbi köréhez hasonlóan — **hívó nélkül**
   marad: a `ShadowAnalysisRunner` NEM kerül be az `analysis_providers.dart`
   Riverpod-gráfjába és NEM hívja az Analyze screen (egyik fájl sincs az
   `allowed_paths`-on). A completion reportban ezt **explicit NEM
   BIZONYÍTOTT**-ként kell rögzíteni: „a shadow-mechanizmus (izoláció,
   diff-riport alak, hiba/cancel-kezelés) tesztekkel bizonyított, de éles
   V1-vs-V2 futás nulla — a `analysisV2RunnerProvider` fail-closed marad, a
   bekötés egy jövőbeli pipeline-összeszerelő kör előfeltétele".

### R7 — Legacy migrációs teszt: „bitre változatlan" → mezőnkénti egyezés (R21 már mérte, hogy a szó szerinti értelmezés hibás)

A §6 „Teljes migrációs teszt" pont „a legacy kulcs **bitre változatlan**"
szövege szó szerint véve `jsonEncode(...) == jsonEncode(legacyPayload)`
egyezést jelentene. **Az E06-R21 saját brief-je pontosan ezt a
megfogalmazást kapta, és a kör kénytelen volt lazítani rá** (E06-R21 §10.4
pont 3): az `AnalyzedSession.toJson()` kulcssorrendje eltér a nyers legacy
JSON-étól, ezért a valódi, tesztelt garancia **mezőnkénti egyezés**
(`test/features/audio_analysis/data/legacy_library_migrator_test.dart:399-409`,
minden legacy mező értéke egyezik, sorrend nem). **R30 ugyanazt a mezőnkénti
egyezés-szabványt kövesse**, ne ismételje meg ugyanazt a menet közbeni
visszavonást: az 50-sessionös migrációs teszt assertion-je mezőnkénti
(`for (final entry in legacyPayload.entries) expect(reencoded[entry.key],
entry.value)` minta), nem `jsonEncode` string-egyenlőség.

A `LegacyLibraryMigrator` (`lib/features/audio_analysis/data/migration/
legacy_library_migrator.dart`, E06-R21, **nincs** az `allowed_paths`-on — ne
módosítsd) `run()`-ja már ma is soha nem törli/írja át a legacy kulcsot
(dokumentált invariáns, ADR 0239 Döntés 5) — az 50-sessionös teszt ezt az
invariánst **méri**, nem egy új mechanizmust épít. Megjegyzés: a
`LegacyMigrationOutcome.failedLegacyIds` mező ma kódolt üres listát ad
vissza (`legacy_library_migrator.dart:72`, sosem töltődik fel) — ne építs
erre assertion-t, csak `attempted`/`migrated`/`skipped`/`failed` számokra és
az `AnalysisRepository.list()` végeredményre.

### R8 — Rollback teszt: nincs kész sablon, csak szerkezeti referencia

Az egyetlen `*rollback_test.dart` a repóban (`test/features/learn/
learn_rollback_test.dart`) **kizárólag** „flag OFF ugyanazt renderli, mint a
legacy build" típusú eseteket fed le — nincs benne ON→migrál→OFF→ellenőriz→
ON-újra kör. A §6 „Rollback-teszt" pontja ennél erősebb: migráció UTÁN
flag OFF-fal a Library V1 útja működjön, a V2 dokumentumok sértetlenek
legyenek lemezen, és flag-visszakapcsolással újra olvashatók legyenek. Az
implementer a `learn_rollback_test.dart` `_flagsOff()`/`_config()`/
`AppConfig`-override-mintáját **csak szerkezeti referenciaként** használja —
a tényleges ON→OFF→ON szekvenciát a `FileAnalysisRepository`/
`AnalysisMigrationVersionStore` (R21) API-jára építve kell megírnia, kész
sablon erre nincs.

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
- [ ] **ADR-státuszok:** a §0.0 R1-ben felsorolt, valós Epic 6 ADR-készlet
      (0215–0221, 0224–0241, 0243, 0246–0249 — **nem** 0200–0211, az a
      tartomány nem létezik) `## Következmények` szakasza frissítve a
      **mért** kimenettel ott, ahol a szöveg jövő időben ír egy azóta
      lezárult körről (különösen 0216 kalibráció, 0220 rollout, 0229
      fusion, 0239 storage — lásd R1 a pontos leképezésért).

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
