# E06-R07 — Signal quality stage · Security review

**Scope:** `codex/e06-r07-signal-quality-stage` @ `71e3401` (fork point / `origin/main` = `52a1acb`), izolált klón `/tmp/review-e06-r07-security`.
**Reviewer discipline:** AGENTS.md §15.1 (risk=high → kötelező dedikált biztonsági review), READ-ONLY, mérve nem csak olvasva ítélve.

## Verdikt: **PASS** — 0 CRITICAL, 0 BLOCKER, 0 MAJOR

Nincs merge-blokkoló lelet. Két előretekintő **NOTE** (mindkettő látens, ebben a
körben el nem érhető). A teljes kör gate zöld (format · analyze · 3× teszt ·
architecture · secrets · l10n).

A merge-et ez a review nem blokkolja.

---

## Nem tárgyalható termékhatárok (AGENTS.md §5) — határonkénti eredmény

| # | Határ | Eredmény | Bizonyíték |
|---|---|---|---|
| 1 | Nyers audio az eszközön marad | **PASS** | Nincs hálózat/storage sink sehol; nincs `HttpClient`/`Dio`/`Socket`/`dart:io` a 3 lib-fájlban (grep NULLA) |
| 2 | Nincs rejtett hálózat kijelentkezve/diagnostics-off állapotban | **PASS** | A modul nulla hálózati hívást tesz; tiszta `List<double>`→report |
| 3 | Nincs secret/nyers-audio/útvonal logban/hibában/commitban | **PASS** | Nincs `print`/logger/`stdout`; a hibaszövegek csak skalár arányt + konstans verziót hordoznak; a gate `secrets` lépése ZÖLD (2201 fájl, 0 lelet) |
| 4 | Cloud/community nem ronthatja az offline alapélményt | **N/A** | Teljesen offline, determinisztikus, egy-menetes |
| 5 | Gyenge confidence nem jelenhet meg biztosként | **PASS** (ebben a körben) | A rövid klip `degradedMetrics={noiseFloorDbfs,tonalness}`-t kap; ld. NOTE-1 az előretekintő lapítási kockázatra |

Prompt-injection / AI-provider felület (ADR 0131–0136): **N/A, megerősítve.**
Nincs provider, tool-hívás, KB-lekérdezés vagy külső szöveg. A bemenet numerikus
PCM, adatként fogyasztva; nincs `eval`/`Function.apply`/`noSuchMethod`/
`dart:mirrors`/dinamikus hívás (grep NULLA).

---

## Feladat-specifikus ellenőrzések — mért eredmények

**1. `dsp_config.dart` bitre változatlan (§5 dec.2 / §6)** — PASS.
`git diff origin/main...HEAD -- lib/features/live/engine/dsp/dsp_config.dart`
→ **üres**; `git diff 52a1acb..HEAD -- …` → **üres**.

**2. Scope-fegyelem** — PASS. `git diff --stat 52a1acb..HEAD` = pontosan a 10
engedélyezett útvonal (3 lib quality-fájl + `public.dart` [+2 additív export
sor] + 3 teszt + RAG chunk 019 + ADR 0224 + kör-dokumentum).
`git diff --name-status | grep -vE '\.(dart|md)$'` → NULLA (nincs új
asset/bináris; nincs provenance/license felület).

**3. Cross-feature importok (OD-01)** — PASS. A `quality/` csak `dart:math`-ot,
`core/foundation/app_result`-ot, `audio_analysis/domain|engine/*`-ot és saját
`quality_thresholds`/`signal_quality_math`-ot importál. Grep `live/engine/dsp`
vagy `features/analyze` után → NULLA. Gépileg is megerősítve a gate
`architecture` lépésével (ZÖLD).

**4. Determinizmus mint integritás (§5 dec.2)** — PASS. Nincs
`DateTime`/`Random`/`Timer`/`Stopwatch`/`dart:io`/`Isolate` a
`signal_quality_math.dart`/`signal_quality_stage.dart` fájlokban (grep NULLA).
Az összegzések fix minta-/keret-sorrendben futnak; a `List.sort` véges
double-ökön. Bitazonosság a `signal_quality_stage_test.dart:161
_expectBitIdentical`-ben állítva (zöld).

**5. Nyers audio / secret szivárgás (§5 dec.1,3)** — PASS. A warningok csak
fix kulcsokat használnak (`quality.recording_{silent,low_level,clipped,
short_clip}`), nincs `messageArgs`, nincs PCM-interpoláció. A
`sourceDisplayName` (a privacy-redaktált név, `analysis_input.dart:7`) sosem
érintett. Az egyetlen string-hordozó dobás a `signal_quality_stage.dart:21`
és `:24` — `ArgumentError.value(activeRegionRatio,…)` /
`(thresholdsVersion,…)` — egy `[0,1]` skalárt és a konstans
`'signal-quality-v1'`-et hordozza, nem nyers audiót/útvonalat/kulcsot. A
fixture-ök szemantikailag mesterségesek (szintetikus szinuszok, impulzus-
sorozatok, glibc-LCG PRNG zaj; a `0x13579`/`0x2468` hex seedek és az
`1103515245`/`12345` konstansok PRNG-paraméterek, nem secretek).

**6/7 (numerikus-határ + játék-minősítés falszifikáció)** — ld. a három mért
próbát lent.

---

## Falszifikációs próbák (ideiglenes rontás → PIROS → `git checkout` visszaállítás)

Mindhárom megerősíti, hogy az őröknek van foguk. Minden próba után a fa tiszta.

**A próba — az `-Infinity`/NaN padló kiszedése (§5 dec.6).**
Módosítás: `signal_quality_math.dart:179` `return _thresholds.silenceFloorDbfs;`
→ `return double.negativeInfinity;`.
`flutter test test/property/analysis_signal_quality_property_test.dart` →
**PIROS**:
```
Invalid argument(s): Signal measurements must be finite.
  …/domain/signal_quality_report.dart 23:7   new SignalQualityReport
  …/engine/quality/signal_quality_stage.dart 93:20  SignalQualityStage.run
```
Megerősíti a fail-closed láncot (`_finiteSample` → `_toDbfs` padló → report
ctor `isFinite` dobás a `signal_quality_report.dart:16-24`-ben). Visszaállítva.

**B próba — clipping-küszöb `>=` → `>` (inkluzív határ).**
Módosítás: `signal_quality_math.dart:36` `>=` → `>`.
`flutter test …/signal_quality_math_test.dart` → **PIROS**: `Expected: <1.0>
Actual: <0.0>  sample=0.999` (`signal_quality_math_test.dart:30`). A
`|x|=0.999` inkluzív cella valódi. Visszaállítva.

**C próba — játékot minősítő warning-kulcs befecskendezése (§5 dec.1).**
Módosítás: feltétel nélküli `AnalysisWarning(messageKey:
'quality.bad_playing')` hozzáadva a `signal_quality_stage.dart` warning
listájához.
`flutter test …/signal_quality_stage_test.dart` → **PIROS**: `Expected: false
Actual: <true>` (`signal_quality_stage_test.dart:76`). A regex-őr
(`(?i)(bad|poor|wrong|sloppy|rossz|gyenge)_?play`) foggal bír. Visszaállítva.

**Alap-/záró gate:** `tools/round-gate.sh test/features/audio_analysis
test/property test/features/analyze` → mind a 8 lépés ZÖLD (beleértve a
`test/features/analyze` + `test/property`-t, ami a DspConfig-változatlanság
acceptance-t és a `dsp_property_test.dart`-ot is fedi). `secrets` ZÖLD (2201
fájl, 0), `architecture` ZÖLD.

---

## NOTE-1 (előretekintő, §5.5 hamis-bizonyosság csíra) — a degraded jelölő egy elhagyható testvér-mezőn utazik

- **Hol:** `signal_quality_stage.dart:89-92` (degraded halmaz) vs. `:93-107`
  (a report `measured=true` alapértékkel épül); `domain/signal_quality_report.dart:13,41`.
- **Hibaforgatókönyv:** bemenet = bármely `< 250 ms`-os klip. A stage
  kiszámolja a `tonalness`/`noiseFloorDbfs`-t, de csak a TESTVÉR
  `SignalQualityStageResult.degradedMetrics`-ben jelöli meg; maga a
  `SignalQualityReport` `measured=true`-val és mezőnkénti degraded-jelölő
  nélkül hordozza az értékeket. Egy **jövőbeli** kör, amely a stage-eredményt
  csak a reportra lapítja (vagy egy work-state, amely elejti a
  `degradedMetrics`-et), egy alacsony-bizonyosságú rövid-klip `tonalness`-t
  biztos, mért értékként tenne láthatóvá.
- **Miért nem sértés most:** a kör bekötetlen — nincs fogyasztó, amely
  komponálná a stage-et (brief §0.0; ADR 0224 §3) —, és a figyelmeztetés
  TÉNYLEG jelen van az egyetlen határon, amit egy fogyasztó ma kapna (a
  stage-eredmény). A kör saját acceptance-e (degraded jelölés a két
  bizonytalan mezőn) teljesül; `signal_quality_stage_test.dart:62` ezt
  állítja.
- **Szabály:** AGENTS.md §5, 5. pont.
- **Irány:** amikor ezt a stage-et később bekötik/perzisztálják (R19
  capability-kapu), a `degradedMetrics`-et vigyék tovább, vagy állítsanak be
  `measured=false`-t/mezőnkénti degraded jelölőt a reporton, hogy a
  figyelmeztetés ne veszhessen el lapításkor.

## NOTE-2 (előretekintő, meglévő R02-szerződés, a diffen kívül) — a report arány-őre NaN-vak

- **Hol:** `domain/signal_quality_report.dart:25-30` — a
  `clippedSampleRatio`/`silentRatio` csak `< 0 || > 1` ellenőrzést kap, míg az
  `overall`/`peakDbfs`/`rmsDbfs`/`noiseFloorDbfs`/`tonalness` `isFinite`
  ellenőrzést is (`:16-24`). Mivel a `NaN < 0` és a `NaN > 1` egyaránt hamis,
  egy `NaN` arány megkerülné az őrt.
- **Hibaforgatókönyv:** egy jövőbeli producer, amely egy arányt `0/0`-n vagy
  más nem-véges úton számol, "érvényes" reportot építhetne `NaN` aránnyal.
- **Miért nem érhető el R07-en keresztül:** ez a fájl **változatlan** ebben a
  körben (nincs a diffben). Az R07 producerei
  (`clippedSampleRatio`/`silentRatio`, `signal_quality_math.dart:32-52`)
  mindig véges `[0,1]`-ben vannak (egész számláló / pozitív hossz; üresre
  0/1). Az A próba mutatja, hogy a véges-őr azonnal elsül, amint egy
  nem-véges érték megjelenne.
- **Szabály:** fail-closed elfajuló bemenetre (validátor-fegyelem). Ugyanaz a
  `< lo || > hi` NaN-fail-open alak, amit az E06-R02-ben már jelöltek, most a
  report-konstruktor határán ismétlődik.
- **Irány (R02-tulajdonos):** vegye fel a két arányt is az `isFinite`
  ellenőrzésbe (vagy adjon hozzá `!ratio.isFinite`-et). Védelem mélységben;
  alacsony prioritás, jelenleg nincs elérési út.

---

## Mit vizsgált a review (evidencia-lista)

Teljesen elolvasva: a kör brief (§5 kötött döntések, §6 acceptance, §10
handoff), ADR 0224, RAG chunk 019, mind a 3 lib-fájl, `public.dart`, mind a 3
tesztfájl, és az R02 domain-típusok (`signal_quality_report.dart`,
`analysis_input.dart`, `analysis_warning.dart`). A 3 lib-fájl grep-elve
nem-determinizmus / logolás / eval / reflection / hálózat után (mind NULLA), a
teljes kör-diff grep-elve secret-mintákra (csak kooperatív
`cancellationToken` — nem auth). 3 falszifikációs próba lefuttatva (mind
PIROS a tervezettnek megfelelően, mind visszaállítva) és a teljes gate
(zöld). Ez a jelentés tervezetten nem reprodukál secret-értéket sehol — csak
helyeket idéz.
