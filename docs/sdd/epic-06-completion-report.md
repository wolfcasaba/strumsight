# Epic 6 — Audio Analysis 2.0: Lezáró jelentés

- **Verzió:** 1.0 (2026-08-13)
- **Körök:** E06-R01–R30
- **Állapot:** implementation evidence recorded; rollout stays at shadow, release blockers remain.

## §33 DoD checklist — cellánkénti evidencia

### Domain és architektúra

- [x] **Létezik verziózott `AnalysisDocument`.** E06-R02, `domain/analysis_document.dart`.
- [x] **A domain Flutter-független.** `tool/check_architecture.dart`, minden E06 gate.
- [x] **Minden metric stabil ID-val és versionnel rendelkezik.** E06-R14.
- [x] **Minden evidence időalapja reprodukálható.** E06-R10 timeline contract.
- [x] **A pipeline stage-ek modulárisak és tesztelhetők.** E06-R09/R22.
- [x] **A V1 adapter rendelkezésre áll a migráció alatt.** E06-R03/R21.
- [x] **Nincs új tiltott cross-feature belső import.** architecture gate.

### Input és lifecycle

- [x] **Mikrofonos és importált input közös boundary mögött van.** E06-R04.
- [x] **WAV parser bounds-safe.** E06-R04 tesztmátrix.
- [x] **Túl nagy vagy hibás input kontrollált failure.** E06-R04.
- [x] **Elemzés megszakítható.** E06-R22 `AnalysisRunHandle.cancel`.
- [x] **Cancel után nincs késői result.** E06-R22 regressziós teszt.
- [x] **Mikrofon és isolate minden útvonalon felszabadul.** E06-R22 lifecycle tesztek.
- [ ] **App background nem hagy hot micet.** PENDING: EVAL-30, Device-lab owner.

### Jelminőség

- [x] **Clipping mérhető.** E06-R07.
- [x] **Túl halk jel mérhető.** E06-R07.
- [x] **Silence ratio mérhető.** E06-R07.
- [x] **Quality warning nem minősíti a felhasználót.** E06-R07 capability contract.
- [x] **Quality gate hat a capabilitykre.** E06-R19.
- [x] **Nyers amplitúdó dynamics célra megmarad.** E06-R16.

### Timeline és harmónia

- [x] **Onset és strum külön event.** E06-R10.
- [x] **Eventek sample indexszel vagy pontos timebase-szel rendelkeznek.** E06-R10.
- [x] **Chord segmentek source és confidence adatot kapnak.** E06-R11.
- [x] **DSP/ML fallback provenance-ben látható.** E06-R09/R11.
- [x] **Beat grid és tempo curve rendelkezésre áll, ha mérhető.** E06-R12.
- [x] **Half/double-time bizonytalanság kezelt.** E06-R12.

### Metrikák

- [x] **Timing metric csak megfelelő reference vagy külön free-play ID mellett jelenik meg.** E06-R14.
- [x] **Rush/drag előjel helyes.** E06-R14.
- [x] **Rhythm consistency dokumentált.** E06-R15.
- [x] **Dynamics sessionön belül mérhető.** E06-R16.
- [x] **Accent metric targetfüggő.** E06-R16.
- [x] **Pitch metric capability gate mögött van.** E06-R17.
- [x] **Technique proxyk kísérletiek, amíg nincs eval.** E06-R18 + EVAL-22–26.
- [x] **Nincs hamis ujj- vagy kéztartás diagnózis.** E06-R18 safety contract.

### Bizonytalanság

- [x] **Minden metric statuszt és confidence-et kap.** E06-R19.
- [x] **Unavailable reason megjeleníthető.** E06-R19/R23.
- [x] **Nyers model score nem probability kalibráció nélkül.** ADR 0216.
- [x] **Low-confidence eredmény nem jelenik meg biztos tényként.** E06-R19.
- [x] **A rendszer képes abstainelni.** E06-R19.

### Insight és integráció

- [x] **Insight determinisztikus szabályból készül.** E06-R20.
- [x] **Minden insight evidence-re hivatkozik.** E06-R20.
- [x] **Practice hotspotból feladat készíthető.** E06-R26 adapter contract, flag OFF.
- [x] **Song target adapter működik.** E06-R26 adapter contract, flag OFF.
- [x] **Tutor csak redaktált facts snapshotot kap.** E06-R26.
- [x] **Vision-hivatkozás csak inferred provenance-szal és közös `SessionTimestamp`-tel kapcsolható az audio evidence-hez.** E06-R26 contract.
- [x] **Practice és Streak credit pontosan egyszer történik.** E06-R26 teszt.

### Persistence

- [x] **Library V2 nem egyetlen nagy SharedPreferences JSON tömb.** E06-R21 `FileAnalysisRepository`.
- [x] **Atomic save működik.** E06-R21.
- [x] **Egy sérült session izolálható.** E06-R21.
- [x] **Legacy migráció idempotens.** E06-R21 + R30 50-session teszt.
- [x] **Custom title megmarad.** R30 50-session teszt.
- [x] **Nyers audio retention alapból kikapcsolt.** ADR 0239.
- [x] **Session és audio törlés teljes.** E06-R27.

### UI

- [x] **Overview capability-aware.** E06-R23.
- [x] **Unavailable metric magyarázott.** E06-R23.
- [x] **Timeline zoomolható és hosszú sessionön is használható.** E06-R24.
- [x] **Hotspot navigáció működik.** E06-R24.
- [x] **Grafikonoknak van szöveges accessibility alternatívája.** E06-R24.
- [x] **Magyar és angol localization parity zöld.** E06-R23/R24.
- [x] **Kis képernyő és nagy szöveg támogatott.** E06-R23/R24.

### Comparison és trend

- [x] **Csak kompatibilis metrika hasonlítható.** E06-R25.
- [x] **Meaningful delta threshold dokumentált.** E06-R25.
- [x] **Inconclusive állapot létezik.** E06-R25.
- [x] **Nem minden nagyobb érték minősül javulásnak.** E06-R25.
- [x] **Trend minimum sample counttal készül.** E06-R25.

### Minőség és rollout

- [x] **V1 baseline dokumentált.** E06-R01.
- [x] **DSP fixture regresszió zöld.** E06-R09, round gate.
- [ ] **Real-audio eval elérhető.** PENDING: EVAL-01–21, valódi címkézett corpus kell.
- [ ] **Confidence calibration riport készül.** PENDING: EVAL-06; ma `identity.v1` (ADR 0216/0249).
- [ ] **Performance baseline és budget dokumentált.** PENDING: EVAL-07/27 és EVAL-32–33, device mérés kell.
- [x] **Cache verzióhelyes.** E06-R28.
- [x] **V2 shadow/opt-in rollout lehetséges.** R30 `ShadowAnalysisRunner`, de hívó nélkül, csak contract-teszt.
- [x] **V1 rollback működik.** R30 OFF→migrál→OFF→olvas→OFF teszt; V1 marad shipping.
- [x] **Privacy dokumentáció frissült.** E06-R27/R30, raw audio nincs a shadow reportban.

## Nyitott tételek

| Tétel | Felelősség | Határidő |
|---|---|---|
| 14 valós eszközös Kör 30 elfogadási pont | Device-lab owner | Merge után |
| Valódi kalibrációs dataset és riport | ML evaluation owner | GOV-30a |
| R29 evaluation CI workflow-bekötés (`.github/workflows/**`, `tool/ci/**`) | Release engineering | GOV-30b |
| V2 pipeline összeszerelés és éles shadow hívó | Audio platform owner | GOV-30c |
| Opt-in/default-on és V1 kivezetés | Product/User | Külön jóváhagyott GOV-kör |

**Összegzés:** 69/74 tétel evidenciával kipipálva; az öt nyitott tétel valódi eszközös vagy governance-bizonyítékot igényel.
