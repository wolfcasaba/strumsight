# ADR 0189 — Vision–audio sync contract (clock mapping)

- **Státusz:** Elfogadva (E05-R21 pre-flight, 2026-08-08)
- **Kör:** E05-R21 — Audio–vision clock mapping és latency kalibráció
- **Implementer motor:** Codex (Terra, `gpt-5.6-terra`, `~/.codex-terra`) — az
  ADR-t az orchesztrátor (Claude Sonnet 5) írta a pre-flightban (ADR 0055,
  pipeline-prompt §2).
- **Epic:** [Chapter 6 — Epic 5: Computer Vision](../sdd/06-epic-05-computer-vision.md) §22
- **Kontext-ADR-ek:** [0179](0179-vision-capability-aware-feedback.md) (a
  `PickingSyncQuality` négy szintje, amit ez a kör kiszolgál),
  [0182](0182-vision-audio-priority-degradation.md) (audio/vision prioritás
  erőforrás-ütközésnél — más réteg, ugyanaz a pár)

> **Számozási megjegyzés:** a kör briefje (2026-08-05, batch-írás) az ADR-t
> előre 0170-re osztotta ki. A pre-flight `tools/round-slots.py reserve-adr`
> hívása 0189-et adott — ugyanaz a mintázat, mint a 0162→0179 átszámozás
> (E05-R09/R16/R18 után, HANDOFF.md), immár negyedszer mérve: a batch-írt
> szám a végrehajtás időpontjára a köztes körök ADR-jei miatt elavul. A
> tényleges szám a foglalóé, nem a brief fejlécéé.

## Kontextus

A kamera és az audio külön pipeline, külön latenciával; a SDD §22.1 közös
monotonic session time-ra várja mindkettőt mapolva. A pre-flight lemérte a
**tényleges** két időalapot ahelyett, hogy egy idealizált formát tételezett
volna fel:

- **Vision oldal** — `CameraTimestamp.microsecondsSinceSessionStart`
  (`lib/core/camera/camera_timestamp.dart`): dokumentáltan monotonic, nincs
  benne wall-clock dátum. A valódi kamera-adapter
  (`lib/core/camera/plugin_camera_capture.dart:238-251`) egy Dart-oldali,
  `initialize()`-kor resetelt/indított elapsed-clockból (`_clock.elapsedMicroseconds`)
  származtatja, és egy szigorú monoton-őrrel kényszeríti a szigorú növekedést
  (`elapsedUs > _lastTimestampUs ? elapsedUs : _lastTimestampUs + 1`) — a
  nullpont a kamera-session indulása, sosem naptári idő.
- **Audio oldal** — `PitchObservation.observedAt`
  (`lib/core/audio/pitch/pitch_observation.dart`): **`DateTime`**, egy
  injektálható `_now` függvényből (alapértelmezett `DateTime.now`) származik,
  a PCM-frame capture pillanatában rögzítve
  (`lib/features/song_trainer/data/audio/live_pitch_observation_gateway.dart:37,63,96,208`)
  és változatlanul továbbadva. Ez **wall-clock**, naptári nullponttal — nem
  létezik ma session-relatív vagy monotonic-tipusú audio timestamp.

A két oldal tehát nemcsak nullpontban, hanem **típusban és garanciában** is
eltér — ez a brief pre-flight-figyelmeztetésének mért tartalma („a mért
hibaosztály: idealizált időalapból számolt referenciacella"): egy fixture-
készlet, ami mindkét oldalra tiszta egész mikroszekundumot tételezne fel,
nem a valódi audio bemenetet tesztelné.

A brief §5/2 bucket-neveit (`poor / acceptable / good / excellent`) a
pre-flight összevetette az SDD §22.4 tervezet-szövegével
(`excellent / good / degraded / unavailable`) és az E05-R19-ben **már
mergelt** `PickingSyncQuality` enummal
(`lib/features/vision/domain/metrics/picking_metrics.dart:75`) — a kettő
eltér, és a brief a **mergelt fogyasztói szerződést** követi, nem a
korábbi tervezet-szöveget. Ez a helyes irány: az R19 gate-je (`good`/
`excellent` ⇒ event-level metrika engedélyezett) ma erre a névkészletre
épül, és ezt a kört ő fogyasztja majd (R22+).

## Döntés

1. **A `ClockMapping` és a rajta belüli aritmetika kizárólag monotonic,
   session-relatív mikroszekundumon dolgozik — sosem `DateTime`-on.**
   A `VisionClock` határa `CameraTimestamp`-et fogad (már monotonic, nincs
   konverzió). Az `AudioClock` határa a mai `DateTime`-tipusú audio
   megfigyelést fogadja, de **azonnal**, a mapping-logika előtt egy rögzített
   referencia-pillanathoz (kalibráció/session kezdete) képest vett
   `Duration`-különbségre alakítja — a `DateTime` objektum maga soha nem jut
   túl ezen a határon. **NEM elfogadható:** `DateTime.now()` hívás a mapping
   bármely ágán (ezt a boundary-konverzió és az injektált óra biztosítja).
2. **Az offset (`offsetUs`) és az opcionális drift (`driftPpm`) mikroszekundum
   / ppm egységben** (SDD §22.2 kontraktus-alak), `confidence` score-ral.
   A drift bekapcsolható, de dokumentált abszolút határon túl **érvényteleníti**
   a mappinget — nem extrapolálunk tovább.
3. **A sync-quality négy bucketje `poor / acceptable / good / excellent`**
   — az E05-R19 már mergelt `PickingSyncQuality` szerződését szolgálja ki,
   nem az SDD §22.4 korábbi tervezet-neveit. A határok konstansként
   dokumentáltak és benchmark alapján konfigurálhatók; **rossz szinkron
   explicit bucket-érték, nem egy némán pontatlanabb szám.**
4. **Kalibráció: kötelező outlier-elutasítás.** Egyetlen elvétett taps/pengetés
   nem mozdíthatja el érdemben az offsetet; az elutasított minták száma a
   confidence egyik bemenete.
5. **Session közbeni újramérés nem ír felül retroaktívan.** Egy új
   `ClockMapping` a mostantól kiadott observationökre vonatkozik; a korábban
   már kiadott observationök időbélyege és a hozzájuk tartozó mapping-
   pillanatkép megmarad (provenance).
6. **Determinisztikus tesztelhetőség:** minden óra és eseménylista injektált;
   nincs implicit rendszerhívás (`DateTime.now`, `Stopwatch()`) a domain
   rétegben.

**NEM elfogadható:** a bucket-határok elmozdítása azért, hogy több esemény
minősüljön `good`-nak (brief §5/2); a wall-clock `DateTime` bármilyen közvetlen
felhasználása a mapping aritmetikájában, akár csak logolásra vagy
összehasonlításra is — csakis a boundary-n számolt `Duration`-különbség.

## Következmények

- Az `AudioClock` a mai audio-pipeline (`lib/core/audio/`, `song_trainer`
  gateway) **egyetlen módosítása nélkül** fogyasztható — a boundary-konverzió
  ezen az ADR-en belüli, új kódban (`vision_clock.dart`) él, a `lib/core/audio/`
  továbbra is tiltott zóna marad ebben a körben.
- A `sync_quality.dart` bucket-neve és négyese szándékosan **azonos alakú**,
  mint a már mergelt `PickingSyncQuality` — egy későbbi kör (R22+) cserélheti
  az injektált enumot erre a valódi forrásra migrációs kockázat nélkül, mert a
  névkészlet és a szemantika (poor/acceptable ⇒ csak session-aggregát,
  good/excellent ⇒ event-level engedélyezett) már ma egyezik.
- Ha egy jövőbeli kör az SDD §22.4 tervezet-neveire akarná „javítani" a
  bucketeket, az a mergelt R19-fogyasztót törné — ez az ADR explicit
  dokumentálja, hogy a döntés tudatos, nem elírás.
- A valós Android audio+camera kalibrációs benchmark (a device-mátrix PENDING
  sora) a bucket-határok **végleges** hangolásának előfeltétele; a kapu-logika
  (bucket enum, outlier-elutasítás, drift-korlát) ettől függetlenül ebben a
  körben kész és tesztelt.

## Elutasított alternatívák

- **Az audio megfigyelés típusát is monotonic `int`-re cserélni ebben a
  körben.** Elvetve: a `lib/core/audio/` és a `pitch_observation.dart` a
  brief tiltott zónája (audio DSP/mikrofon-út módosítása kizárva); a
  boundary-konverzió a jelenlegi kontraktus mellett old meg mindent, plusz
  kör nélkül.
- **Egyetlen `visionAvailable`-szerű `synced` boolean.** Elvetve: ugyanaz az
  indoklás, mint ADR 0179 — elrejti a degradált eseteket, false feedbackhez
  vezet, és az R19 gate-je már négy szintre épül.
- **A bucket-neveket az SDD §22.4 tervezet-szövegére igazítani.** Elvetve:
  az R19 mergelt kódja a `poor/acceptable/good/excellent` névkészletre épül;
  az átnevezés egy már lezárt kör fogyasztói szerződését törné (H1/H2 jellegű
  kockázat) egy sosem implementált tervezet-szöveg kedvéért.
- **Wall-clock offset (audio `DateTime` mínusz vision session-start
  `DateTime.now()` egyszeri mérése) mint gyorsabb megoldás.** Elvetve: a
  vision oldalon nincs is `DateTime` nullpont (csak `Stopwatch`-alapú
  elapsed), és egy egyszeri wall-clock mérés érzékeny lenne NTP-/időzóna-
  ugrásra a session alatt — pontosan amit a SDD §22.1 és a brief döntés #1
  kizár.
