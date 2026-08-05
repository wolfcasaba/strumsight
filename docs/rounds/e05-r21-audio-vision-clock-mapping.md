# E05-R21 — Audio–vision clock mapping és latency kalibráció

- **Státusz:** PREPARED (előre megírva 2026-08-05, kód olvasva: main @ `5d082dc`)
- **SDD-kör:** [`docs/sdd/06-epic-05-computer-vision.md`](../sdd/06-epic-05-computer-vision.md) Kör 21; §22
- **Branch:** `codex/e05-r21-audio-vision-clock-mapping`
- **Előfeltétel:** **E05-R06, E05-R12, E05-R19 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/vision/domain/sync/vision_clock.dart",
  "lib/features/vision/domain/sync/clock_mapping.dart",
  "lib/features/vision/domain/sync/sync_quality.dart",
  "lib/features/vision/application/sync_calibration_controller.dart",
  "lib/features/vision/public.dart",
  "test/features/vision/domain/clock_mapping_test.dart",
  "test/features/vision/application/sync_calibration_controller_test.dart",
  "test/property/clock_mapping_property_test.dart",
  "docs/adr/0170-vision-audio-sync-contract.md",
  "docs/rounds/e05-r21-audio-vision-clock-mapping.md",
]
gate_tests = [
  "test/features/vision",
  "test/property/clock_mapping_property_test.dart",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** `origin/main` + E05-R06/R12/R19 merge; **mérd
> össze a két időalapot**: a `CameraFrame` capture timestampjének forrását (R06)
> és az audio oldal mai óráját (`lib/core/audio/capture/audio_capture.dart`,
> `pitch_observation.dart`) — a brief §5.1-e a MÉRT alakhoz igazítandó, nem
> fordítva (a mért hibaosztály: idealizált időalapból számolt referenciacella).
> **ADR 0170** előre kiosztva. PREPARED→PLANNING, brief commit előbb.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED.** Előre kiosztott ADR: **0170** (audio–vision szinkron-szerződés).

## 1. Cél

A camera observationök és az audio strum-események **közös session-időre**
helyezése: offset- és opcionális drift-becslés, kalibrációs flow, outlier-
elutasítás, és a sync-minőség **bucketek** kiszámítása — amiket az R19 kapuja
már használ.

## 2. Jelenlegi állapot (mért, `5d082dc` + megelőző körök)

- Az R19 **injektált** sync-minőséggel dolgozik; ez a kör köti be a valódi
  forrást. A stroke-metrikák szerződése tehát **nem változik**.
- Az audio oldalon a pitch/strum megfigyelés a `lib/core/audio/` alatt él
  (mikrofon → PCM → DSP); a **wall clock nem** része a jelenlegi
  observation-útnak — a pre-flight méri, milyen időalapot ad ki ma.
- A `CameraFrame` (R03/R06) hordoz capture timestampet; az R02 runbookja méri
  meg valós eszközön, hogy ez monotonic-e (PENDING).

## 3. Scope

**Benne:** `VisionClock` / `AudioClock` / `ClockMapping` contract, offset- és
drift-becslés outlier-elutasítással és confidence score-ral, kalibrációs
folyamat (több pengetés/taps esemény), latency-komponensek (capture, inference,
observation) rögzítése, sync-quality bucketek **benchmark alapján
konfigurálhatóan**, és a session közbeni **újramérés**.

**Kívül — TILOS:** audio DSP-paraméter, mikrofon-út módosítása, fusion (R22),
UI (a kalibrációs képernyő az R24 része), metrika-szerződés átírása.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../domain/sync/vision_clock.dart` | ÚJ | óra-absztrakciók |
| `.../domain/sync/clock_mapping.dart` | ÚJ | offset + drift |
| `.../domain/sync/sync_quality.dart` | ÚJ | bucketek |
| `.../application/sync_calibration_controller.dart` | ÚJ | kalibrációs flow |
| `lib/features/vision/public.dart` | meglévő | additív export |
| `test/features/vision/*`, `test/property/clock_mapping_property_test.dart` | ÚJ | tesztek |
| `docs/adr/0170-*.md` | ÚJ | szinkron-szerződés |
| `docs/rounds/e05-r21-*.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más; `lib/core/audio/`; `docs/rag`; DSP.
Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **A mapping monotonic órát használ; a wall clock NEM része a szinkronnak.**
   **NEM elfogadható:** `DateTime.now()` a mapping bármely ágán (időzóna-,
   NTP- és felhasználói óraállítás-érzékeny lenne).
2. **Rossz szinkron explicit `degraded`** — nem „kicsit pontatlan érték".
   A bucketek (`poor / acceptable / good / excellent`) határai konstansként
   dokumentáltak, és az R19 kapuja ezekre hivatkozik. **NEM elfogadható:**
   a bucket-határok elmozdítása azért, hogy több esemény minősüljön `good`-nak.
3. **Outlier-elutasítás kötelező** a kalibrációban (egyetlen elvétett taps ne
   rontsa el az offsetet), és az elutasított minták száma a confidence bemenete.
4. **A drift-becslés opcionális, de ha be van kapcsolva, korlátos**: a becsült
   drift abszolút értéke a dokumentált határon túl **érvényteleníti** a
   mappinget (nem „extrapolálunk tovább").
5. **Session közbeni újramérés lehetséges**, és az új mapping **nem írja át
   visszamenőleg** a már kiadott observationöket (a provenance megmarad).
6. **Determinisztikus tesztelhetőség:** injektált óra, injektált eseménylista.

## 6. Acceptance criteria

- [ ] **Offset-mátrix:** ismert, mesterségesen eltolt eseménypárokra a becsült
      offset a valódihoz ≤ dokumentált hibán belül; legalább 5 eltolás-érték,
      köztük 0 és negatív.
- [ ] **Outlier-teszt:** N valid + 1 durván hibás minta → az offset gyakorlatilag
      változatlan (számmal), és az elutasított minta megjelenik a statisztikában.
- [ ] **Bucket-mátrix:** minden bucket-határ **alatt / rajta / fölött** —
      a cellák értékét `python3 -c` számolja (a §10-ben idézve). A `good` alsó
      határa mindkét oldalról mérve.
- [ ] **Property teszt (`PROPERTY_SEED`):** lineáris drift mellett a mapping
      hibája a horizonton belül a dokumentált korlát alatt marad; a hibaarány
      %-alapú küszöbbel.
- [ ] **Monotonicitás-teszt:** a mapping bemenetén nem monotonic időbélyeg →
      kontrollált hiba (nem néma átrendezés).
- [ ] **Újramérés-teszt:** a session közbeni recalibráció után a **korábbi**
      observationök időbélyege változatlan.
- [ ] **Valódi-sértés próba (§10):** `DateTime.now()` bevezetése a mappingbe →
      a monotonicitás/determinizmus teszt PIROS → visszaállítás.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/vision test/property/clock_mapping_property_test.dart
```

Külön processzek, nincs `&&`/pipe/`tail`. A valós Android audio+camera
kalibrációs benchmark a device-mátrix **PENDING** sora — a bucket-határok
végleges hangolása ehhez kötött, de a **kapu-logika** itt zöld.

## 8. Implementációs sorrend

1. Időalapok mérése (pre-flight) → §5.1 pontosítása.
2. RED: offset-, outlier-, bucket-mátrix.
3. `ClockMapping` + outlier-elutasítás + confidence.
4. Bucketek + kalibrációs controller + ADR 0170; gate.

## 9. Kockázatok

- **A két óra eltérő alapja** (pl. audio minta-index vs kamera nanosecond) —
  a pre-flight mérése nélkül a fixture-ök idealizáltak lennének; ezért a
  §5.1 kifejezetten a mért alakhoz igazítandó.
- **A bucket-határ a fixture-höz igazodik**, nem a valósághoz; a valós
  benchmark PENDING marad, és a hangolás **külön** kör lesz, ha kell.

**STOP:** wall clock bevezetése, bucket-lazítás vagy audio-út módosítása
helyett dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e05-r21-audio-vision-clock-mapping-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
