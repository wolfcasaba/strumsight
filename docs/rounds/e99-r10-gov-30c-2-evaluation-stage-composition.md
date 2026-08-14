# E99-R10 (GOV-30c-2) — A V2 lánc MÁSODIK fele: referencia, illesztés, metrikák, capability

- **Státusz:** PLANNING (pre-flight lezárva 2026-08-14, `main @ fa79f1d0`)
- **Típus:** **governance-kör** — a GOV-30c második lépcsője (ADR 0250 §4)
- **Kör-azonosító:** `E99-R10`. Emberi neve **GOV-30c-2**.
- **Branch:** `codex/e99-r10-gov-30c-2-evaluation-stage-composition`
- **Előfeltétel:** `E99-R09` (GOV-30c-1) merge-elve (PR #259, `cb76db0f`)
- **Brief szerzője:** Claude (Opus 5) · **Implementáció:** Codex (Terra)
- **Előre kiosztott ADR:** [`0251`](../adr/0251-analysis-target-seeding-and-evaluation-stage-composition.md)
  — **MÁR MEGÍRVA az orchesztrátor által, a `docs/adr/` a TILOS zónában van.**
- **Folytatás (NEM ez a kör):** GOV-30c-3 — insights/hotspots, a
  `AnalysisDocument` összeállítása, és **csak ott** az
  `analysisV2RunnerProvider` felülírása. **A briefje szándékosan még nincs
  megírva.** A háromlépcsős vágás indoka az ADR 0251 §4-ben mérve.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/audio_analysis/engine/analysis_work_state.dart",
  "lib/features/audio_analysis/engine/stages/evaluation_stages.dart",
  "test/features/audio_analysis/engine/analysis_work_state_test.dart",
  "test/features/audio_analysis/engine/stages/evaluation_stages_test.dart",
  "test/features/audio_analysis/engine/evaluation_pipeline_composition_test.dart",
  "docs/rounds/e99-r10-gov-30c-2-evaluation-stage-composition.md",
]
gate_tests = [
  "test/features/audio_analysis/engine/evaluation_pipeline_composition_test.dart",
  "test/features/audio_analysis/engine/stages/evaluation_stages_test.dart",
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

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 1. Cél

A GOV-30c-1 megépítette az ingest-lánc hét stage-ét a PCM-bemenettől az
eseménysávig. Ez a kör az **értékelő** felet teszi hozzá: a referencia
beemelését, az illesztést, a metrikákat és a capability/confidence feloldást.

**Ez a kör sem kapcsol be semmit.** Az `analysisV2RunnerProvider` érintetlen
marad és a végén is `StateError`-t dob; a dokumentum-összeállítás és a
bekötés a GOV-30c-3 dolga.

## 2. Jelenlegi állapot — mért tények

### 2.1 Amit a GOV-30c-1 hagyott (a bemenetünk)

`engine/analysis_work_state.dart` mezői (mérve, `main @ fa79f1d0`):

```
input · legacyEvidence? · preprocessedAudio? · signalQuality?
pitchFrames[] · pitchSegments[] · chordSegments[]
beatGrid? · tempoCurve? · events[] · suppressedEvents[]
warnings[] · unavailableCapabilities{}
```

A hét ingest-stage id-ja `IngestStageIds` alatt:
preprocessing, signalQuality, legacyEvidence, pitch, harmony, rhythm, events.

### 2.2 A HIÁNYZÓ LÁNCSZEM: a referencia nincs a munkaállapotban

Ez a kör központi mért ténye. Az illesztés kötelező bemenete egy referencia:

```dart
// engine/alignment/event_aligner.dart:22-25
AlignmentResult align({
  required List<AnalysisEvent> observed,
  required List<ExpectedEvent> expected,
  required Duration beatDuration, …
```

és a timing-metrikák ezen keresztül függenek tőle
(`metrics/timing_metrics.dart:26` — `required AlignmentResult alignment`).

**A munkaállapotban NINCS referencia-mező, és a `ValidatedPcmAnalysisInput`
sem hordoz ilyet** (`domain/analysis_input.dart:81-82`: `input` + `warnings`).

### 2.3 De a referencia LÉTEZIK és elérhető — csak nem jut el idáig

```dart
// domain/target/analysis_target.dart:32
final class AnalysisTarget {
  final String id;                        final int targetVersion;
  final AnalysisTargetKind kind;          // practice | song | custom
  final AnalysisTargetTimebase timebase;  // session | media
  final List<ExpectedEvent> expectedEvents;
  final List<String> expectedChords;
  final List<int> expectedNotes;
  final List<AnalysisTargetSection> sections;
}
```

És **már elő is állítja** két, E06-R26-ban merge-elt adapter:
`application/adapters/practice_analysis_adapter.dart` és
`application/adapters/song_analysis_adapter.dart`.

> **Ezt a bejárást a brief azért mondja ki tételesen, mert az előző kör (`E99-R09`)
> F1/MAJOR leletét pont az okozta, hogy egy acceptance-cella olyan bemenetet
> várt, amit az engedélyezett modulok egyike sem állított elő.** Itt a
> referencia-út végig van mérve: a típus létezik, a termelője létezik, és a
> §5.1 megmondja, hogyan jut a munkaállapotba.

### 2.4 A hiány NEM hiba: a rendszer előre számolt vele

```dart
// engine/confidence/capability_resolver.dart:11-17
required this.signalQuality, required this.eventCount,
required this.modelConfidence, required this.alignmentQuality,
required this.mode, required this.hasReferenceTarget,
required this.modelAvailable,
```

A `hasReferenceTarget` **már paraméter**. A négy `AnalysisMode`
(`freePlay`, `practiceTarget`, `songReference`, `importedRecording`) közül
kettőnél nincs referencia — ilyenkor az illesztés-függő capability-k
**elvesznek, nem buknak**.

### 2.5 A wrapolandó modulok — mind léteznek

| modul | belépési pont (mért) | referencia kell? |
|---|---|---|
| `alignment/` | `EventAligner.align(...)`, `tolerance_policy.dart` | **IGEN** |
| `metrics/timing_metrics.dart` | `required AlignmentResult alignment` | **IGEN** |
| `metrics/timing_hotspots.dart` | illesztésre épül | **IGEN** |
| `metrics/rhythm_metrics.dart` | `required List<AnalysisEvent> events` | nem |
| `metrics/pitch_metrics.dart` | pitch-szegmensek | nem |
| `metrics/dynamics_metrics.dart` | `required PreprocessedAudio audio, List<StrumEvent> events, SignalQualityReport signalQuality` | nem |
| `metrics/accent_analysis.dart`, `subdivision_analysis.dart`, `transition_analysis.dart`, `technique_proxies.dart` | események / szegmensek | nem |
| `metrics/metric_gate.dart`, `dynamics_gate.dart` | kapuk a fentiek fölé | nem |
| `confidence/capability_resolver.dart`, `confidence_combiner.dart`, `calibration_table.dart`, `capability_thresholds.dart` | a fenti kimenetek | nem |

**Mind végig-review-zott és tesztelt** (E06-R14…R20). A kör NEM ír
DSP-matematikát.

### 2.6 Dokumentum-összeállító MA NINCS

`grep -rln "AnalysisDocument(" lib/features/audio_analysis/` → csak a
`domain/analysis_document.dart`, a `data/analysis_document_codec.dart` és a
`data/legacy_analyze_adapter.dart`. Az engine nem állít össze dokumentumot —
ez a GOV-30c-3 feladata, és ez az egyik oka a háromlépcsős vágásnak.

## 3. Scope

**Benne van:**

1. `AnalysisWorkState` bővítése: `target` (nullable `AnalysisTarget`),
   `alignment` (nullable `AlignmentResult`), `metrics`, `capabilityReports`,
   `overallConfidence`.
2. A `seed` kiegészítése úgy, hogy a hívó **megadhassa** a referenciát.
3. Az értékelő stage-ek `AnalysisStage<AnalysisWorkState, AnalysisWorkState>`
   alakban: alignment → metrikák → capability/confidence.
4. Az értékelő lánc kompozíciója + failure-classifier.
5. Tesztek: a referencia hiányának és meglétének mátrixa, adapterenkénti
   viselkedés, végigfutó kompozíció.

**NINCS benne (tilos):**

- **Az `analysisV2RunnerProvider` felülírása vagy bármely flag mozgatása.**
  Acceptance-cella (A9).
- `AnalysisDocument` összeállítása, insights, hotspot-rangsor — GOV-30c-3.
- DSP-matematika írása vagy meglévő engine-modul módosítása (AGENTS.md §9).
- Az `application/adapters/**` bármilyen módosítása. A referenciát a
  **hívó** adja át; hogy a meglévő adapterek hogyan kötődnek be, az a
  GOV-30c-3 kérdése.
- `public.dart` barrel (a tesztek közvetlenül importálnak — mérve: 67 import).
- `docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `engine/analysis_work_state.dart` | a referencia + értékelő artefaktumok mezői |
| `engine/stages/evaluation_stages.dart` | **ÚJ** — az értékelő stage-ek, a lánc és a classifier |
| `test/…/engine/analysis_work_state_test.dart` | az új mezők invariánsai |
| `test/…/engine/stages/evaluation_stages_test.dart` | **ÚJ** — adapterenkénti viselkedés |
| `test/…/engine/evaluation_pipeline_composition_test.dart` | **ÚJ** — végigfutó lánc, referenciás és referencia nélküli ágon |
| `docs/rounds/e99-r10-…md` | a §10 handoff |

**Tilos zóna:** `lib/features/audio_analysis/application/**` ·
`lib/features/audio_analysis/public.dart` · `lib/core/flags/**` ·
`engine/stages/ingest_stages.dart` **tartalma** (olvasni kell, írni nem) ·
minden meglévő `engine/**` modul tartalma · `docs/adr/**` · `tools/**` ·
`.github/**`.

## 5. Kötött architekturális döntések (ADR 0251)

### 5.1 A referencia a munkaállapot SEED-jén érkezik, nem stage-ben termelődik

`AnalysisWorkState.seed(input: …, target: AnalysisTarget?)`. A `target`
**nullable**, és a lánc semelyik stage-e nem állítja elő — a hívó adja át.

*Miért nem stage:* a referencia nem az audióból származik, hanem a
gyakorlat/dal kontextusából. Egy „target-építő stage" a DSP-láncba húzná be
az alkalmazásréteget.

**NEM elfogadható gyengítés:** a referencia „kikövetkeztetése" az
eseményekből, ha nincs megadva. Az saját maga ellen mérné a játékot.

### 5.2 Referencia nélkül DEGRADÁL, nem bukik

Ha `target == null` vagy `expectedEvents` üres:

- az illesztő stage **nem fut le hibával**, hanem `alignment = null`-t hagy;
- a `hasReferenceTarget: false` megy a `CapabilityResolver`-nek;
- az illesztés-függő capability-k az `unavailableCapabilities`-be kerülnek;
- a **referencia-független** metrikák (rhythm, pitch, dynamics, accent,
  subdivision, transition, technique) **ugyanúgy kiszámolódnak**.

**NEM elfogadható gyengítés:** üres `expected` listával meghívni az
`EventAligner`-t és a kapott „minden hibás" eredményt valódi illesztésként
publikálni. Az nem hiányzó adat, hanem HAMIS adat — a felhasználó 0%-os
pontosságot látna azért, mert nem volt mihez mérni.

### 5.3 A degradálási politika a kompozícióé

| stage | hiba esetén |
|---|---|
| alignment | **degradálható** — az illesztés-függő capability-kkel |
| metrikák (mind) | **degradálható** — metrikánként a saját capability-jével |
| capability/confidence | **fatális** — ez a dokumentum kötelező mezője |

**NEM elfogadható gyengítés:** a capability/confidence degradálhatóvá tétele.
Enélkül a dokumentum nem tudja megmondani, mit ér, amit mutat.

### 5.4 A `hasReferenceTarget` MÉRT, nem feltételezett

A `CapabilityResolver` `hasReferenceTarget` argumentuma a munkaállapot
tényleges `target` mezőjéből származik, nem az `AnalysisMode`-ból. Egy
`practiceTarget` módú futás is kaphat üres referenciát (hiányos gyakorlat-terv),
és olyankor a mérés az igazság, nem a mód.

### 5.5 A kör semmit nem kapcsol be

Az `analysisV2RunnerProvider` érintetlen; a kör végén is `StateError`.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A `seed` elfogad `target`-et, és `null` a default | `analysis_work_state_test.dart` |
| A2 | Minden értékelő stage `AnalysisStage<AnalysisWorkState, AnalysisWorkState>` | fordítás + `evaluation_stages_test.dart` |
| A3 | **Referenciával**: az illesztés lefut, a timing-metrikák megjelennek | kompozíciós teszt, „van target" ág |
| A4 | **Referencia nélkül**: `alignment == null`, timing-capability az `unavailableCapabilities`-ben, és **nincs** timing-metrika a listában | kompozíciós teszt, „nincs target" ág |
| A5 | Referencia nélkül a referencia-FÜGGETLEN metrikák ugyanúgy kiszámolódnak | kompozíciós teszt — a két ág metrika-halmazának különbsége PONTOSAN az illesztés-függő halmaz |
| A6 | Az `EventAligner` **nem hívódik meg** üres `expected` listával | `evaluation_stages_test.dart` — injektált illesztő, hívás-számláló |
| A7 | `hasReferenceTarget` a `target` mezőből jön, nem az `AnalysisMode`-ból | teszt: `practiceTarget` mód + üres target → `hasReferenceTarget: false` |
| A8 | A capability/confidence hibája MEGÁLLÍTJA a láncot | kompozíciós teszt, fatális cella |
| A9 | `analysisV2RunnerProvider` a kör után is `StateError`-t dob | `git diff` — az `application/**` érintetlen |
| A10 | Nulla DSP-matematika az adapterekben | scope-audit + review |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A `target` nem jut el a seedből az illesztő stage-ig | A3 |
| Üres `expected` listával hívja az `EventAligner`-t | **A6** (hívás-számláló) és A4 (a timing-metrika megjelenne) |
| Referencia hiányában az EGÉSZ metrika-blokkot kihagyja | A5 |
| Referencia hiányában a láncot megbuktatja | A4 |
| `hasReferenceTarget`-et az `AnalysisMode`-ból számolja | **A7** |
| A capability/confidence degradálhatóra állítva | A8 |
| Minden metrika-stage fatális | A4 (egy hiányzó pitch-metrika megbuktatná a futást) |
| A kör „hasznosságból" felülírja a providert | A9 |

**A referencia három kötelező cellája** (a határ: van-e használható referencia):

| Cella | Bemenet | Elvárt |
|---|---|---|
| nincs referencia | `target == null` | `alignment == null`, timing-capability unavailable, a többi metrika MEGVAN |
| a határon | `target != null`, de `expectedEvents` ÜRES | ugyanaz, mint fent — **az üres lista nem referencia** |
| van referencia | `target` legalább egy `ExpectedEvent`-tel | illesztés lefut, timing-metrikák megjelennek |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** vedd ki az üres-lista
ellenőrzést, hogy az `EventAligner` üres `expected`-del is meghívódjon → az
**A6** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/audio_analysis/engine/evaluation_pipeline_composition_test.dart test/features/audio_analysis/engine/stages/evaluation_stages_test.dart test/features/audio_analysis/engine/analysis_work_state_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli, és a
kör `unknown`-ba fut (L254).

## 8. Implementációs sorrend

1. `AnalysisWorkState` bővítés (`target`, `alignment`, `metrics`,
   `capabilityReports`, `overallConfidence`) + a seed — teszttel.
2. Az illesztő stage az 5.2 üres-referencia ágával.
3. A referencia-FÜGGETLEN metrika-stage-ek (rhythm, pitch, dynamics, accent,
   subdivision, transition, technique) — ezek nem függenek a 2. lépéstől.
4. A referencia-FÜGGŐ metrika-stage-ek (timing, timing hotspots).
5. Capability/confidence stage, `hasReferenceTarget` az 5.4 szerint.
6. Kompozíció + failure-classifier az 5.3 táblázat szerint.
7. A §6.1 három referencia-cellája + a valódi-sértés próba.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **Az üres referencia csendes elfogadása.** Ez a kör legveszélyesebb
  hibamódja: az `EventAligner` üres `expected`-del futtatva technikailag ad
  eredményt, ami 0%-os pontosságnak látszik. Az A6 pont ezt méri
  hívás-számlálóval, nem kimenet-ellenőrzéssel.
- **A metrika-modulok bemeneti típusai eltérnek** (`StrumEvent` vs
  `AnalysisEvent` vs pitch-szegmens). A típus-illesztés önálló, tesztelt
  konverzió legyen a munkaállapot fájljában — nem rejtett DSP az adapterben
  (ugyanaz a csapda, mint a GOV-30c-1 §5.2-ben).
- **A munkaállapot elhízása.** Csak az kerüljön bele, amit a GOV-30c-3
  dokumentum-összeállítása ténylegesen olvas: `metrics`, `capabilityReports`,
  `overallConfidence`, `alignment`.
- **A kör mérete.** Kilenc metrika-modul + illesztés + capability egyetlen
  körben sok. Ha a §8 4. lépése után a gate nem hozható zöldre, az `stopped`
  és brief-revízió — NEM a mérce lazítása.

## 10. Implementation handoff — a Codex tölti ki

## 11. Review — a Claude tölti ki
