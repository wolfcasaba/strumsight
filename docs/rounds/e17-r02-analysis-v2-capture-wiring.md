# E17-R02 — Az Analysis V2 felvevő-ág bekötése (3 képernyő)

- **Státusz:** PREPARED (előre megírva 2026-09-05, kód olvasva: `main @ b17e08ef`) — **`hold`: A kör az `audioAnalysisV2Enabled` kapu MÖGÉ köt be. A kapu `forEnvironment`-ben MINDEN környezetben `false` — a bekötés tehát mérhető (flag-gated route), de a felhasználó számára csak egy külön rollout-döntés után látszik**
- **Típus:** Chapter 17 (Teljes bekötés), Kör 2
- **Kör-azonosító:** `E17-R02`
- **Branch:** `<motor>/e17-r02-analysis-v2-capture-wiring`
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0521` — a szám ELŐZETES; a foglaló a kör indulásakor adja a véglegeset (mérve: nyolc egymást követő körön át a queue ADR-oszlopa elavult volt).
- **Fejezet-terv:** [`docs/plans/chapter-17-full-wiring.md`](../plans/chapter-17-full-wiring.md)

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "az analysis v2 felvevő-ág bekötése (3 képernyő)"` — a kör pre-flightjának KÖTELEZŐ lefuttatnia és a találatokat a §2-be beépítenie; a brief előre megírt állapotában a §2 a `main @ b17e08ef` mérésein áll.

## 0.0 MIÉRT `hold`

A kör az `audioAnalysisV2Enabled` kapu MÖGÉ köt be. A kapu `forEnvironment`-ben MINDEN környezetben `false` — a bekötés tehát mérhető (flag-gated route), de a felhasználó számára csak egy külön rollout-döntés után látszik. **Mi oldja fel:** ez a kör route-szinten bekötheti a hármat a meglévő `audioAnalysisV2Enabled` kapu alatt; a `hold` oka, hogy előbb az `E17-R01` mintája (kompozíciós bekötés + reachability-cella) záruljon le mértként.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/app/routing/app_router.dart",
  "lib/features/audio_analysis/application/analysis_providers.dart",
  "lib/features/audio_analysis/public.dart",
  "test/features/audio_analysis/capture_wiring_test.dart",
  "docs/rounds/e17-r02-analysis-v2-capture-wiring.md",
  "test/app/navigation/adaptive_scaffold_test.dart",
  "test/app/navigation/tab_state_restoration_test.dart",
  "test/app/navigation/legacy_route_redirect_test.dart",
  "test/app/navigation/",
]
native_gate = false
gate_tests = [
  "test/features/audio_analysis/",
  "test/features/analyze/",
  "test/app/routing/",
  "test/app/navigation/adaptive_scaffold_test.dart",
  "test/app/navigation/tab_state_restoration_test.dart",
  "test/app/navigation/legacy_route_redirect_test.dart",
  "test/app/navigation/",
]
```

## 0. Kör-jelzés és STOP-protokoll

Scope-ütközés esetén a kimenet a brief-REVÍZIÓ, nem a scope önkényes tágítása: állítsd meg a kört (`stopped`), és írd le, melyik §-t kell módosítani.

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

## 1. Cél

Az Analysis V2 felvevő-ága (`AnalysisHomeScreen` → `AnalysisRecordingScreen` → `AnalysisProcessingScreen`) a szállított kompozícióból elérhető, a meglévő `audioAnalysisV2Enabled` kapu alatt.

## 2. Jelenlegi állapot — mért tények (`main @ b17e08ef`)

- A három capture-képernyő a fában él (`lib/features/audio_analysis/presentation/capture/`), és mindhárom `reachable: false`.
- Mindhárom TISZTA prezentációs widget: injektált függőségeket vár (`recentAnalyses`, `onStartRecording`, `onImportFile` · `recorder`, `onFinished`, `onCancel` · `state`, `onCancel`) — nincs bennük saját adat-beszerzés.
- A `AnalysisRecorder` (`lib/features/audio_analysis/data/capture/analysis_recorder.dart:15`) és az `analysis_providers.dart` LÉTEZIK; a feature-ben `0` db `UnimplementedError` van.
- A már routolt V2 képernyők (`AnalysisOverview`, `AnalysisTimeline`, `AnalysisMetricDetail`) MÉRT mintát adnak: mind az `audioAnalysisV2Enabled` kapu alatt élnek.
- **Mért kikötés:** a legacy `AnalyzeScreen` felvevő útja MŰKÖDIK (mic-handshake, `AnalyzePhase.recording`/`micDenied` ágak) — ez a kör NEM törött funkciót javít, hanem a párhuzamos V2 ágat teszi elérhetővé.

## 3. Scope

**Benne van:** A három capture-képernyő route-jai az `audioAnalysisV2Enabled` kapu alatt · a kompozíciós providerek, amik a `AnalysisRecorder`-t és az `AnalysisState`-et a szállított forrásból adják · a fázis-átmenetek (home → recording → processing → overview) navigációja.

**NINCS benne (tilos):**

- A legacy `AnalyzeScreen` bármely módosítása.
- Az `audioAnalysisV2Enabled` alapértékének megváltoztatása — ez rollout-döntés, nem bekötés.
- Új DSP- vagy elemzési viselkedés.

## 4. Engedélyezett fájlok

(lásd az `ai-router` blokk teljes listáját)

**A pin-őrök jogosultsága (S10/S11, mérve: E13-R16/F9 full-gate 32867296946, E13-R17/H3 `test/app/navigation/` +33 → +30 −3):** a fenti listán szereplő, a briefen KÍVÜL élő pin-tesztek azért kerültek az `allowed_paths`-ba ÉS a `gate_tests`-be, mert a bekötés a route által renderelt képernyő TÍPUSÁT mozdíthatja el. A jogosultság PONTOSAN ennyi: a lecserélt képernyő típusának átírása a pinnelő cellában. **Cella törlése, `skip`-je vagy gyengítése TILOS** — ha egy cella a típus-átíráson túl válik pirossá, az a kör BLOKKOLÓ lelete, nem a cella hibája.


## 5. Kötött architekturális döntések (ADR 0521)

### 5.1 A három képernyő a MEGLÉVŐ `audioAnalysisV2Enabled` kapu alatt kerül be, új flag NEM születik

A V2 ág három társ-képernyője már ez alatt él. Egy negyedik, capture-specifikus flag két igazságforrást csinálna ugyanabból a rollout-döntésből.

### 5.2 A capture-képernyők TISZTA prezentációs jellege megmarad: a függőségeket a route-építő adja, nem a widget olvassa

A három widget ma injektált paramétereket vár. Ha a bekötés `ref.watch`-ot tesz beléjük, a meglévő widget-tesztjeik (7+16+23 cella) egyszerre válnak hamissá és újraírandóvá — a bekötésnek a KOMPOZÍCIÓBAN kell élnie.

### 5.3 A legacy `AnalyzeScreen` bájtra érintetlen marad

A V2 párhuzamos ág. A legacy útvonal a ma MŰKÖDŐ felvevő; egy közös refaktor a kör scope-ján kívüli regressziót nyitna.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Mindhárom capture-képernyő `reachable: true` és `flagGated: true` (`audioAnalysisV2Enabled`) | `dart run tool/check_screen_reachability.dart --format json` |
| A2 | `audioAnalysisV2Enabled=true` mellett a home → recording → processing átmenet valós providerekkel végigmegy | widget-teszt valós `ProviderContainer`-rel |
| A3 | `audioAnalysisV2Enabled=false` mellett a három route NEM létezik, és a legacy Analyze útvonal változatlanul elérhető | router-teszt mindkét flag-álláson |
| A4 | A három capture-widget konstruktora változatlan (injektált paraméterek), a diff nem visz `ref.watch`-ot a widgetekbe | `git diff` + a meglévő widget-tesztek zölden |
| A5 | A legacy `AnalyzeScreen` fájlja a diffben nem szerepel | `git diff --name-only` |

### 6.1 Falszifikációs próba

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** Kösd a `AnalysisRecordingScreen`-t a kapun KÍVÜLRE (feltétel nélküli route), futtasd a gate-et → az A3 cellának PIROSNAK kell lennie → állítsd vissza.

Minden fenti acceptance-cella MÉRT állítás: a §7 gate-parancsa futtatja őket, és a falszifikációs próba bizonyítja, hogy a cellák tényleg pirosra váltanak a hibás implementáción.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/audio_analysis/ test/features/analyze/ test/app/routing/ test/app/navigation/adaptive_scaffold_test.dart test/app/navigation/tab_state_restoration_test.dart test/app/navigation/legacy_route_redirect_test.dart test/app/navigation/
```

A gate a `format` → `analyze` → `test <minden útvonal külön>` → `architecture` lépéseket KÜLÖN processzként futtatja (a box mért OOM-csapdája miatt a `flutter analyze && flutter test` lánc tilos).

## 8. Implementációs sorrend

1. A §2 mért tényeinek ÚJRAMÉRÉSE a kör indulásakor (a brief alapja elmozdulhatott).
2. A §5 döntéseinek rögzítése az ADR-ben.
3. Az implementáció a §4 engedélyezett fájljain belül.
4. A §6 acceptance-cellák tesztjei.
5. A §6.1 valódi-sértés próba lefuttatása és a §10-be dokumentálása.
6. A §7 gate futtatása csonkítatlan kimenettel.

## 9. Kockázatok

- **A widget-szerződés elrontása.** `ref.watch` a prezentációs widgetbe 46 meglévő tesztcellát tesz hamissá (5.2).
- **A legacy felvevő megsértése.** A ma MŰKÖDŐ Analyze út regressziója a legdrágább hibaosztály itt (5.3, A5).
- **A rollout-döntés elkövetése.** A flag alapértékének megváltoztatása termékdöntés, nem bekötés (§3 tiltás).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
