# E05-R21 — Audio–vision clock mapping és latency kalibráció

- **Státusz:** PLANNING (pre-flight lezárva 2026-08-08, kód mérve: main @ `6ae3ec7`)
- **SDD-kör:** [`docs/sdd/06-epic-05-computer-vision.md`](../sdd/06-epic-05-computer-vision.md) Kör 21; §22
- **Branch:** `codex/e05-r21-audio-vision-clock-mapping`
- **Előfeltétel:** **E05-R06, E05-R12, E05-R19 merge** — mind a három MERGED
  (PR #168 / `a43f8c1`; PR #183 / `113976a`; PR #192 / `a38e0e0`).
- **Brief szerzője:** Claude (batch, 2026-08-05) · **Pre-flight revízió:**
  Claude Sonnet 5 (2026-08-08) · **Implementáció:** Codex (Terra)

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
  "docs/adr/0189-vision-audio-sync-contract.md",
  "docs/rounds/e05-r21-audio-vision-clock-mapping.md",
]
gate_tests = [
  "test/features/vision",
  "test/property/clock_mapping_property_test.dart",
]
native_gate = false
```

> ✅ **Pre-flight ELVÉGEZVE (2026-08-08).** Eredmény lásd §0.0 és az új §5.1.
> Rövid összefoglaló: a két időalap **típusban és garanciában is** eltér (nem
> csak nullpontban) — ez a §5.1-be került. Az előre kiosztott **ADR 0170
> ELAVULT** (negyedszer mérve ugyanaz a batch-írás/foglalás-drift minta, mint
> a 0162→0179 átszámozásnál) — a `tools/round-slots.py reserve-adr` **0189**-et
> adott, ez a kötelező szám, lásd `docs/adr/0189-vision-audio-sync-contract.md`.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PLANNING.** Négy mért pont, a pipeline-prompt §1 két kötelező mérési
szabálya szerint (elérhetetlen cél-státusz / erőforrás-tulajdonlás), plusz a
brief saját kötelező pre-flight-feladata (időalap-összevetés):

1. **ADR-szám elavult, javítva 0170→0189.** A brief 2026-08-05-i batch-írása
   idején 0170 volt a legmagasabb szabad szám; a köztes E05-R09..R20 körök
   pre-flightjai azóta 0171–0188-at foglaltak le. `tools/round-slots.py
   reserve-adr --round E05-R21` (race-safe, `O_CREAT|O_EXCL`) → **0189**. Ez a
   negyedik mérés ugyanerre a mintára (HANDOFF.md: 0162→0179, E05-R09/R16/R18
   után) — a brief fejlécében szereplő szám sosem tekinthető véglegesnek,
   csak a foglaló kimenete. Minden `0170` hivatkozás a briefben és az
   `allowed_paths`-ban `0189`-re javítva; a `docs/execution/pipeline-queue.tsv`
   ADR-oszlopa (`0170`) szándékosan **változatlan** marad — azt a driver
   vezeti (AGENTS.md §4 tiltás), nem forrás-igazság az ADR-számra.
2. **A két időalap típusban ÉS garanciában eltér, nem csak nullpontban** —
   ez volt a brief kifejezett pre-flight-feladata. Mérve:
   - **Vision:** `CameraTimestamp.microsecondsSinceSessionStart`
     (`lib/core/camera/camera_timestamp.dart`) — dokumentáltan monotonic
     `int`, nincs benne naptári dátum. A tényleges gyártó
     (`lib/core/camera/plugin_camera_capture.dart:238-251`) egy Dart-oldali,
     `initialize()`-kor indított elapsed-clockból (`_clock.elapsedMicroseconds`)
     számol, szigorú monoton-őrrel (`elapsedUs > _lastTimestampUs ? elapsedUs
     : _lastTimestampUs + 1`).
   - **Audio:** `PitchObservation.observedAt`
     (`lib/core/audio/pitch/pitch_observation.dart:16`) — **`DateTime`**,
     egy injektálható `_now` függvényből (alapértelmezett `DateTime.now`)
     ered, PCM-frame capture pillanatában rögzítve
     (`lib/features/song_trainer/data/audio/live_pitch_observation_gateway.dart:37,63,96,208`).
     Wall-clock, naptári nullponttal — **nincs ma session-relatív vagy
     monotonic-tipusú audio timestamp** a kódban.
   - Következmény a §5.1-ben és az ADR 0189 Döntés 1-ben: az `AudioClock`
     határa `DateTime`-ot fogad, de a mapping-aritmetika előtt azonnal
     referencia-pillanathoz képesti `Duration`-ra alakítja — a brief eredeti
     „a mapping monotonic órát használ" döntése (§5/1) ETTŐL a
     boundary-konverziótól függetlenül tartható, tehát **nem kellett
     gyengíteni**, csak a bemeneti alakot pontosítani.
3. **Sync-quality bucket-nevek keresztellenőrizve az R19 mergelt
   fogyasztójával.** A brief §5/2 `poor / acceptable / good / excellent`
   négyese **eltér** az SDD §22.4 tervezet-szövegétől
   (`excellent / good / degraded / unavailable`), de **egyezik** az E05-R19-ben
   már mergelt `PickingSyncQuality`-vel
   (`lib/features/vision/domain/metrics/picking_metrics.dart:75`,
   `docs/reviews/e05-r19-picking-hand-stroke-metrics-review.md` APPROVED).
   A brief tehát **helyesen** a mergelt kódot követi, nem a tervezetet — ez
   dokumentálva most az ADR 0189-ben is, hogy egy jövőbeli kör ne „javítsa
   vissza" az SDD-szöveg neveire (ami törné az R19 gate-jét). **Nincs
   brief-módosítás szükséges ezen a ponton** — csak a döntés rögzítése.
4. **Erőforrás-tulajdonlás (pipeline-prompt §1 2. szabálya): nem
   releváns.** A brief egyetlen acceptance-cellája sem rendel lease/lock/
   handle/subscription-t egy réteghez (a kalibráció és a mapping tisztán
   domain-objektum, nincs `.acquire()`-hívás vagy mikrofon/kamera-birtoklási
   állítás a §5 döntések között) — a `grep -rn "\.acquire("` ellenőrzés ezen
   a briefen nem alkalmazható, dokumentálva, nem kihagyva.

## 1. Cél

A camera observationök és az audio strum-események **közös session-időre**
helyezése: offset- és opcionális drift-becslés, kalibrációs flow, outlier-
elutasítás, és a sync-minőség **bucketek** kiszámítása — amiket az R19 kapuja
már használ.

## 2. Jelenlegi állapot (mért, `5d082dc` + megelőző körök)

- Az R19 **injektált** sync-minőséggel dolgozik; ez a kör köti be a valódi
  forrást. A stroke-metrikák szerződése tehát **nem változik**.
- Az audio oldalon a pitch/strum megfigyelés a `lib/core/audio/` alatt él
  (mikrofon → PCM → DSP); **mérve (§5.1): a mai `PitchObservation.observedAt`
  éppen hogy `DateTime`, azaz wall-clock** — a boundary-konverzió emiatt
  kötelező elem, nem opcionális finomítás.
- A `CameraFrame` (R03/R06) hordoz capture timestampet; **mérve (§5.1): a
  `CameraTimestamp` monotonic, Dart-oldali elapsed-clockból származik**
  (a natív platform capture-metaadatot nem használja) — az R02 runbook
  valós-eszközös monotonicitás-mérése emiatt megerősítő, nem feltáró jellegű,
  és PENDING marad a device-mátrixban.

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
| `docs/adr/0189-*.md` | ÚJ | szinkron-szerződés (0170→0189, §0.0 pont 1) |
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

### 5.1 Mért időalapok (pre-flight, 2026-08-08)

A két bemeneti időalap **mai, tényleges** alakja — a fixture-öket és az
`AudioClock`/`VisionClock` boundary-t ehhez kell igazítani, nem egy
idealizált egységes formához:

| | Típus | Nullpont | Garancia | Forrás |
|---|---|---|---|---|
| **Vision** | `CameraTimestamp` (`int`, µs) | kamera-session indulása | monotonic, szigorú-növekvő őrrel kényszerítve | `lib/core/camera/camera_timestamp.dart`; gyártó: `lib/core/camera/plugin_camera_capture.dart:238-251` (Dart-oldali elapsed-clock) |
| **Audio** | `DateTime` | naptári epoch | wall-clock; injektálható (`_now`, alapértelmezett `DateTime.now`) | `lib/core/audio/pitch/pitch_observation.dart:16`; gyártó: `lib/features/song_trainer/data/audio/live_pitch_observation_gateway.dart:37,63,96,208` |

**Ebből következő kötelező tervezési szabály (ADR 0189 Döntés 1):** a
`VisionClock` a `CameraTimestamp`-et változtatás nélkül fogadja (már
monotonic). Az `AudioClock` a mai `DateTime`-bemenetet fogadja a
boundary-n, de **a mapping-aritmetika előtt**, egyetlen lépésben egy
rögzített referencia-pillanathoz (kalibráció/session kezdete) képesti
`Duration`-különbségre alakítja — a `ClockMapping`, a kalibrációs
outlier-elutasítás és a drift-becslés kizárólag ezen a származtatott,
session-relatív mikroszekundum-értéken dolgozik, sosem a nyers `DateTime`-on.
A monotonicitás-teszt (§6) ezt a boundary-konverziót is fedi: ha a
`DateTime`-sorozat a rendszeróra módosulása miatt visszafelé ugrik, az
`AudioClock`-nak ezt kontrollált hibaként kell jeleznie, nem néma
átrendezéssel.

A `lib/core/audio/` és a `pitch_observation.dart` **tiltott zóna marad**
(§3/§4) — ez a szabály a boundary-konverzió ELHELYEZÉSÉRE vonatkozik (az ÚJ
`vision_clock.dart`/`clock_mapping.dart` fájlokban), nem az audio-oldali
timestamp típusának módosítására.

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

1. Időalapok mérése (pre-flight, ELVÉGEZVE) → §5.1 pontosítva.
2. RED: offset-, outlier-, bucket-mátrix.
3. `ClockMapping` + outlier-elutasítás + confidence.
4. Bucketek + kalibrációs controller + ADR 0189 (kiosztva); gate.

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
