# E06-R17 — Review

Brief: `docs/rounds/e06-r17-monophonic-pitch-capability.md`
Diff: `2c08dc5b..2c02f031` (`codex/e06-r17-monophonic-pitch-capability`); implementer-only commit: `f5d5d613..2c02f031`
Javító kör: `b3a38a29..26f38dd6` (`test(analysis): close pitch capability coverage gaps`, 3 fájl, csak `test/**`)
Reviewer: Claude (Opus 5, független review-ág) · Dátum: 2026-08-12 (első kör) / 2026-08-12 (javító kör)
Verdikt: ~~CHANGES REQUESTED~~ → **APPROVED** (javító kör után)

## Összegzés

**Javító kör után: BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 2 (nem blokkol)**
(első körben: BLOCKER: 0 · MAJOR: 3 · MINOR: 2 · NOTE: 2 — ld. alább, változatlanul
dokumentálva, minden lelet lezárási bizonyítékkal kiegészítve)

Az F1–F5 mind LEZÁRVA a `26f38dd6` javító commitban, a jelentés első verziójában
kifejezetten előírt "Ellenőrzés" mutáció-próbákkal, egy ÚJ, friss
`/tmp/review-e06-r17-fix1` klónban, saját kézzel megismételve (nem az
implementer állítására hagyatkozva):

- **F1 (MAJOR → FIXED):** az eredeti teszt fixture-je immár `hasMonophonicTarget:
  true` + valós, egyébként mindent teljesítő frame-készlet (nem
  `hasMonophonicTarget: false` konfundálással); ÚJ, dedikált teszt is került
  (`'flag OFF precedes unavailable OD-01 evidence checks'`,
  `hasMonophonicTarget: true, frames: []`), amely KIFEJEZETTEN a sorrendet
  méri. Mindkét eredeti mutáció (relokáció, teljes törlés) most PIROSRA vált.
- **F2 (MAJOR → FIXED):** a property teszt immár ténylegesen hívja a
  `MonophonicPitchSegmentBuilder.build`-et és a `buildGatedPitchMetrics`-et 20
  frame-es, realisztikus (stabil-görbe + jitter) bemeneten, és minden metrika
  ÉRTÉKÉT (nem csak a bemeneti value objecteket) ellenőrzi típus-specifikus
  invariánsokra. A `centsBetween → double.nan` mutáció most azonnal PIROSRA
  vált, ugyanazzal a kivétellel, mint a fix fixture-tesztek.
- **F3 (MAJOR → FIXED):** új, valódi 4-hangos, EGYIDEJŰLEG összekevert
  szinusz-akkord fixture (`_fourVoiceChord`, A-C#-E-A, forgó domináns hanggal),
  a valódi `PitchFrameExtractor`-en átfuttatva, `unavailable`/`polyphonicInput`
  + hívásszámláló==0 bizonyítva — PLUSZ egy beépített negatív kontroll (a
  spread-kapu explicit kikapcsolásával `available`-re vált ugyanazon
  frame-eken, bizonyítva, hogy az elutasítás oka valóban a spread). A spread-
  ellenőrzés saját kikapcsolásommal ez a teszt is PIROSRA vált.
- **F4 (MINOR → FIXED):** a „silence yields only unvoiced frames" teszt immár
  a `PitchCapabilityGate.evaluate`-et is hívja, és `status=unavailable`,
  `reason=insufficientEvents`-et vár — pontosan az eredetileg kért kiegészítés.
- **F5 (MINOR → FIXED):** egysoros komment került a voiced-arány fixture fölé,
  amely megmagyarázza a 69/70/71 (nem 0.349/0.350/0.351) választás okát.
- **F6/F7 (NOTE):** a javító kör csak `test/**`-et érintett, a `docs/rounds/`
  §10 handoff és az ARB-elrendezés (kozmetikai) VÁLTOZATLAN — ezek nem
  blokkolók, follow-up-ként nyitva maradnak.

Kiegészítés: a `b3a38a29` commit egy PÁRHUZAMOSAN futott, független dedikált
security review (`docs/reviews/e06-r17-monophonic-pitch-capability-security.md`),
verdikt **PASS** (0 CRITICAL/BLOCKER/MAJOR, 1 MINOR — `buildPitchMetrics`
O(szegmens×célhang) skálázás, bekötetlen modulra nem blokkoló, „must-fix-before"
egy jövőbeli untrusted/hosszú-audio bekötésnél —, 2 NOTE). Nincs átfedés vagy
ellentmondás az én megállapításaimmal.

A gate FORMAI oldala kifogástalan: 15/15 fájl az `allowed_paths`-on belül, a
teljes `tools/round-gate.sh test/features/audio_analysis test/property
test/core test/features/tuner` saját kézzel, izolált klónban, elölről
lefuttatva **teljesen zöld** (format, analyze, mind a 4 célzott teszt-útvonal,
architecture, secrets, l10n — ld. Gate-bizonyíték táblázat). A Tuner-paritás
bizonyítottan érintetlen fájllal áll.

A CONTENT oldalon három throwaway mutáció-próba (F1, F2, F3 alatt
dokumentálva, mind visszaállítva, a working tree jelenleg tisztán a
`2c02f031`-gyel azonos) azt mutatja, hogy a kör legkockázatosabb, KÉTSZERES
pre-flight-felülvizsgálaton átesett garanciája — a flag-kapu ELSŐSÉGE — a
SAJÁT dedikált tesztje által gyakorlatilag védtelen (a teszt egy másik,
véletlenül egybeeső feltétel miatt marad zöld akkor is, ha a flag-ellenőrzést
teljesen törlöm a forrásból), a kötelező NaN-mentesség property teszt nem a
valódi számítási láncot méri (egy `centsBetween`-be injektált NaN-bug mellett
zöld marad, miközben 9/11 fixture-teszt lefagy), és a „polifónia-kapu"
kritérium a brief által név szerint előírt négyhangos akkord-fixture helyett
egy kéthangú szekvenciális proxyval van lefedve. Egyik hiba SEM
produkciós-kód-defekt (a forráskód olvasása + a próbák is megerősítik: a
tényleges viselkedés a brief szerint helyes) — mindhárom **teszt-lefedettségi**
rés a kör legkritikusabb, névvel nevezett garanciáin.

**Fontos folyamat-megjegyzés (nem számít bele a BLOCKER/MAJOR/MINOR/NOTE
összesítésbe, mert nem kód-defekt):** a review indulásakor
(2026-08-12 12:2x UTC) az implementer `2c02f031` commitja **nem volt fent**
az `origin/codex/e06-r17-monophonic-pitch-capability`-n (sem a megosztott
`/home/ubuntu/music-theory` local branch-en) — csak egy különálló
implementer-klónban (`/home/ubuntu/ss-terra-e06-r17`, tiszta working tree,
`[ahead 1]`) létezett, `git push` nélkül. A review tartalmi részét emiatt
onnan (read-only fetch, SHA egyezés `2c02f0314c0dd0be3e8056abe5a210c9b5a5c439`
ellenőrizve) forrásoztam az izolált `/tmp/review-e06-r17` klónba. E jelentés
push-a (lásd alul) a `2c02f031`-et is felviszi `origin`-ra, mivel a helyi
branch-em erre épül — ez oldja fel a hiányt, de érdemes az orchestrátor
pipeline-jában megnézni, miért jelezte a #3 lépés („Verify scope audit +
commit implementer diff") kész-nek magát push nélkül.

## Acceptance criteria (brief §6)

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | Frekvencia-mátrix (7 cella, A4+6 húr, ±2 cent, exact MIDI) | ✅ | `pitch_frame_extractor_test.dart` 7 parametrizált teszt (E2..A4), mind zöld a saját gate-futásban |
| 2 | Cent-offset küszöb hármas (+9.99/+10.00/+10.01, inkluzív +10.00) | ✅ | `pitch_metrics_test.dart:30-46` „intonation threshold is inclusive at +10.00 cents" — explicit 3-cellás tábla, zöld |
| 3 | Voiced-arány küszöb hármas (0.349/0.350/0.351, inkluzív 0.350) | ✅ | `pitch_capability_gate_test.dart:23-39` (javító kör után): 69/70/71/200, MOST kommenttel dokumentálva a szubsztitúció oka. Funkcionálisan változatlanul helyes — F5 FIXED |
| 4 | Polifónia-kapu: 4-hangos akkord → `unavailable`, hívásszámláló==0, chord/ritmus külön fut | ✅ | ÚJ teszt (`pitch_frame_extractor_test.dart`, „four simultaneous sine chord is unavailable before metric calculation"): valódi 4-szólamú, egyidejű szinusz-akkord a valódi `PitchFrameExtractor`-en át → `unavailable`/`polyphonicInput`, `metricCalls==0`, + beépített negatív kontroll. Saját spread-kikapcsolás mutáció-próbával megerősítve — F3 FIXED. „chord/ritmus külön fut": továbbra is a megosztott könyvtár zöld állapotával (322 teszt) közvetetten igazolt |
| 5 | Csend és zaj: mindkettő `unavailable`, dokumentáltan melyik ok | ✅ | Zaj: változatlanul ✅. Csend: a „silence yields only unvoiced frames" teszt MOST már hívja a `PitchCapabilityGate.evaluate`-et, `status=unavailable`/`reason=insufficientEvents` explicit ellenőrizve — F4 FIXED |
| 6 | Vibrato ±30 cent, 5 Hz → EGY szegmens, stabilityCents≈30±5 | ✅ | `pitch_frame_extractor_test.dart`, zöld (változatlan) |
| 7 | Hangváltás A4→C5 → KÉT szegmens, határ ±40 ms | ✅ | `pitch_frame_extractor_test.dart`, zöld (változatlan) |
| 8 | Tuner-paritás: tesztfája átírás nélkül zöld, diff nem érint `lib/core/audio/**`/`lib/features/tuner/**` | ✅ | `git diff --stat 2c08dc5b..26f38dd6` mindkét útvonalra továbbra is üres; `test test/features/tuner`: 42/42 zöld, saját gate-futásban (javító kör is test-only, nem érinti) |
| 9 | Flag-kapu: `analysisPitchEnabled=false` ELSŐKÉNT, OD-01 (a)-(d) előtt, `notApplicable`, hívásszámláló==0 | ✅ | A dedikált teszt fixture-je javítva (`hasMonophonicTarget: true` + valós frame-ek), ÚJ dedikált sorrend-teszt hozzáadva. Mindkét eredeti mutáció (relokáció, teljes törlés) most PIROSRA vált, saját kézzel megismételve — F1 FIXED |
| 10 | NaN-mentesség property: véletlen bemenetre minden Hz/cents véges, confidence [0,1] | ✅ | A property teszt átírva: MOST ténylegesen hívja a `MonophonicPitchSegmentBuilder.build`-et és `buildGatedPitchMetrics`-et 20 frame-es realisztikus bemeneten, minden metrika-érték típus-specifikus invariánsát ellenőrzi. `centsBetween → double.nan` mutáció-próba azonnal PIROSRA vált — F2 FIXED |

## Scope-audit

```
git diff --stat f5d5d613..2c02f031   →  15 files changed, 1157 insertions(+), 1 deletion(-)
```

Mind a 15 fájl szerepel a brief `allowed_paths` listáján (1:1 egyezés, sem
hiány, sem többlet). Tilos zóna (`lib/core/audio/**`, `lib/features/tuner/**`,
`lib/features/analyze/**`, `lib/features/live/**`) — **nulla** érintett fájl,
mind az implementer-commitra, mind a teljes kör-diffre (`2c08dc5b..2c02f031`)
ellenőrizve.

**Javító kör (`b3a38a29..26f38dd6`) scope-audit:**

```
git diff --stat b3a38a29..26f38dd6   →  3 files changed, 137 insertions(+), 25 deletions(-)
test/features/audio_analysis/engine/pitch_capability_gate_test.dart   | 17 ++-
test/features/audio_analysis/engine/pitch_frame_extractor_test.dart   | 56 ++++
test/property/analysis_pitch_property_test.dart                       | 89 +++--
```

Mind a 3 fájl a brief `allowed_paths` `test/**` bejegyzésén belül; **nulla**
produkciós-kód fájl érintett. Tilos zóna továbbra is **nulla** érintett fájl a
TELJES körre (`2c08dc5b..26f38dd6`) nézve is.

## Megállapítások

### F1 — MAJOR — A flag-kapu dedikált tesztje nem bizonyítja a saját nevében szereplő tulajdonságot

- **Fájl:** `test/features/audio_analysis/engine/pitch_capability_gate_test.dart:6-21`
- **Probléma:** A `'flag OFF short-circuits before every OD-01 check and metric
  callback'` teszt `hasMonophonicTarget: false`-t ÉS `analysisPitchEnabled:
  false`-t is beállítja egyszerre. Mivel `hasMonophonicTarget: false` ÖNMAGÁBAN
  is `notApplicable`-t ad (OD-01 (a) ág, `pitch_capability_gate.dart:66-74`),
  a teszt attól függetlenül zöld marad, hogy a flag-ellenőrzés ELSŐKÉNT fut-e,
  UTOLJÁRA fut-e, vagy akár teljesen HIÁNYZIK-e a forrásból.
- **Mutáció-próba (elvégezve, visszaállítva):**
  1. A flag-ellenőrzést a metódus VÉGÉRE helyeztem (az `available` return elé,
     tehát minden OD-01 (b)-(d) feltétel UTÁN, de még `onAvailable()` hívása
     előtt). Eredmény: `pitch_capability_gate_test.dart` mind a 4 tesztje
     ZÖLD marad — a dedikált teszt nem veszi észre az átrendezést, mert egyik
     inputja sem olyan kombináció (flag=false + valós target + egyébként
     mindent teljesítő frame-ek), ahol a sorrend megfigyelhető különbséget
     okozna.
  2. A flag-ellenőrzést TELJESEN semlegesítettem (`if (!analysisPitchEnabled
     && false)`). Eredmény: a dedikált gate-teszt TOVÁBBRA IS zöld (a
     `hasMonophonicTarget: false` konfundálás miatt); egyedül a
     `pitch_metrics_test.dart` „disabled or polyphonic capability…" tesztje
     bukik (`status` `available`-re vált `notApplicable` helyett) — ez a
     teszt VÉLETLENÜL fedi le a tulajdonságot (valós `target`, tiszta
     440 Hz-es frame-ek), noha nem elsődlegesen erre lett tervezve.
  - Mindkét mutáció visszaállítva (`cp` a mentett eredetiből,
    `git diff --stat` üres); a teljes pitch-tesztkör utána zöld.
- **Hatás:** Egy jövőbeli, jóhiszemű refaktor (pl. a feltételek olvashatósági
  átrendezése) csendben megszegheti az ADR 0235 Döntés 5 legfontosabb,
  KÉTSZERES pre-flight-körön átment garanciáját, és a NEVE SZERINT pontosan
  erre írt teszt ezt nem venné észre — csak egy másik fájl egy másik tesztje,
  amely nem dokumentálja, hogy ezt a szerepet is betölti.
- **Kötelező javítás:** a dedikált teszt fixture-jét szét kell választani: egy
  eset `analysisPitchEnabled: false, hasMonophonicTarget: true` VALÓS,
  egyébként mindent teljesítő frame-készlettel (ahogy a
  `pitch_metrics_test.dart`-beli `_frames()` teszi), hogy a flag-ellenőrzés
  önmagában, konfundálás nélkül bizonyítható legyen.
- **Ellenőrzés:** az új/módosított teszt a fenti mindkét mutációra (relokáció
  ÉS teljes törlés) pirosra váltson.
- **Státusz:** **FIXED** (`26f38dd6`). Javítás: a `'flag OFF short-circuits…'`
  fixture-je `hasMonophonicTarget: false → true` + `frames: []` →
  `_frames(total: 20, voiced: 20)`-re cserélve; ÚJ dedikált teszt
  (`'flag OFF precedes unavailable OD-01 evidence checks'`,
  `hasMonophonicTarget: true, frames: []`) kifejezetten a sorrendet méri.
  **Újra-ellenőrizve** (`/tmp/review-e06-r17-fix1`, saját kézzel, ugyanaz a
  két mutáció): (1) flag-check relokáció az `available` elé →
  `'flag OFF precedes…'` PIROS (`notApplicable` várt, `unavailable` kapott),
  a másik 4 teszt zöld; (2) flag-check teljes törlése (`if (... && false)`) →
  MOST MINDKÉT releváns teszt PIROS (`'flag OFF short-circuits…'` is:
  `notApplicable` várt, `available` kapott). Mindkét mutáció visszaállítva,
  `git diff --stat` üres utána.

### F2 — MAJOR — A „NaN-mentesség" property teszt nem hívja a kör egyetlen számítási függvényét sem

- **Fájl:** `test/property/analysis_pitch_property_test.dart:12-39`
- **Probléma:** A teszt közvetlenül konstruál `PitchFrame` és
  `MonophonicPitchSegment` value objecteket, MINDEN mezőt már eleve véges,
  `random.nextDouble()`-alapú kifejezésekkel töltve fel (pl.
  `centsOffset: random.nextDouble() * 100 - 50`). Sosem hívja a
  `PitchFrameExtractor.extract`, `MonophonicPitchSegmentBuilder.build`,
  `PitchCapabilityGate.evaluate`, sem a `buildPitchMetrics`/`buildGatedPitchMetrics`
  függvényeket — vagyis a kör tényleges, `math.log`/medián/percentilis/
  dropout-arány számítású kódját SOHA nem futtatja. Az `.isFinite` állítások
  gyakorlatilag azt bizonyítják, hogy a `PitchFrame`/`MonophonicPitchSegment`
  konstruktorok saját maguk validálnak — ami már a fix `pitch_frame.dart`/
  `monophonic_pitch_segment.dart` konstruktor-tesztjeiből is következik.
- **Mutáció-próba (elvégezve, visszaállítva):** a
  `monophonic_pitch_segment_builder.dart`-beli megosztott `centsBetween()`
  függvényt (amelyet a szegmens-építő, a kapu spread-számítása ÉS a metrika-
  motor hibaszámítása is használ) feltétel nélkül `double.nan`-re
  cseréltem.
  - `flutter test test/property/analysis_pitch_property_test.dart` → **ZÖLD**
    marad („All tests passed!") — a property teszt nem veszi észre.
  - `flutter test test/features/audio_analysis/engine/pitch_frame_extractor_test.dart`
    → **9/11 teszt PIROS**, `Invalid argument(s): Pitch segment cents values
    must be finite.` kivétellel (a `MonophonicPitchSegment` konstruktor maga
    dobja) — a hiba valódi és súlyos, csak nem a property teszt kapja el.
  - Visszaállítva (`cp` a mentett eredetiből, `git diff --stat` üres); utána
    a `test/features/audio_analysis/engine` könyvtár és a property teszt
    EGYÜTT futtatva 235/235 zöld.
- **Hatás:** a brief §6 utolsó, név szerint „NaN-mentesség property"-ként
  hivatkozott kritériuma formailag teljesül (a teszt létezik, fut,
  `PROPERTY_SEED` konvenciót követ), de VALÓS regresszió-védelmet nem ad a
  kör legkockázatosabb aritmetikájára (log/median/percentilis/osztás). A
  HORIZON-konvenció („New DSP behaviour ⇒ add a randomized property, not only
  fixed fixtures", CLAUDE.md) szellemével ez nem egyeztethető össze.
- **Kötelező javítás:** a property teszt véletlen, de érvényes tartományból
  vett FREKVENCIA-MINTÁKAT (vagy legalább véletlen `PitchFrame`-listákat)
  vezessen át ténylegesen a `MonophonicPitchSegmentBuilder.build` és/vagy a
  `buildPitchMetrics` függvényeken, és az EREDMÉNY mezőin ellenőrizze a
  végesség/tartomány-invariánsokat — ne a bemeneti value objectek saját
  validációját tesztelje vissza.
- **Ellenőrzés:** a fenti `centsBetween → double.nan` mutáció a javított
  property teszt mellett pirosra váltson.
- **Státusz:** **FIXED** (`26f38dd6`). Javítás: a teszt teljesen átírva —
  trial-onként 20 `PitchFrame`-et generál egy stabil frekvencia-görbe körül
  (±30 cent jitter), ténylegesen hívja a `MonophonicPitchSegmentBuilder.build`-et
  ÉS a `buildGatedPitchMetrics`-et, majd minden szegmens-mezőt ÉS minden
  publikált metrika-értéket (típus-specifikus: Scalar→isFinite,
  Percentage→[0,1], Duration→nem-negatív) ellenőriz. **Újra-ellenőrizve**
  (ugyanaz a `centsBetween → double.nan` mutáció): a property teszt MOST
  azonnal PIROS, ugyanazzal a kivétellel
  (`Invalid argument(s): Pitch segment cents values must be finite.`,
  `MonophonicPitchSegmentBuilder._segmentFor`-ból), mint a fix
  fixture-tesztek. Mutáció visszaállítva, `git diff --stat` üres.

### F3 — MAJOR — A polifónia-kapu fixture-je nem a brief által név szerint előírt négyhangos akkord

- **Fájlok:** `test/features/audio_analysis/engine/pitch_capability_gate_test.dart:39-54`,
  `test/features/audio_analysis/engine/pitch_metrics_test.dart:67-88`
- **Probléma:** a brief §6 („Polifónia-kapu") és §6.1 mérce-mátrixa szó
  szerint „négyhangos akkord-fixture"-t ír elő. A tényleges tesztek egy
  **kéthangú, szekvenciális** frame-listát adnak a kapunak közvetlenül
  (`110 Hz × 20 frame` majd `440 Hz × 20 frame` konkatenálva) — sem valódi
  4-hangos akkord waveform nincs, sem a `PitchFrameExtractor`/valódi YIN nem
  fut rajta; a teszt csak a kapu SPREAD-küszöbének (>100 cent) elszigetelt
  logikáját méri.
- **Mutáció-próba (elvégezve, visszaállítva — a task 6(b) pontja szerint):** a
  spread-ellenőrzést semlegesítettem (`if (false && spread > maximumPitchSpreadCents)`).
  Eredmény: **2 teszt vált pirosra** —
  `pitch_capability_gate_test.dart`: „polyphonic proxy blocks metrics before
  the callback" (`unavailable` helyett `available`) és
  `pitch_metrics_test.dart`: „disabled or polyphonic capability…"
  (`reason` `polyphonicInput` helyett `null`). Ez megerősíti: a KAPU LOGIKÁJA
  ténylegesen védett, csak a FIXTURE TÍPUSA tér el az előírttól.
  Visszaállítva, `git diff --stat` üres, utána zöld.
- **Hatás:** a §5.4 architekturális döntés („Polifonikus bemenetre nincs
  hamis note score") a kör LEGMAGASABB tétjű garanciája. Egy valódi 4-hangos
  akkord a tényleges YIN-detektoron átfuttatva NEM feltétlenül produkál
  ugyanolyan nagy, tiszta spread-et, mint egy kézzel írt kéthangú blokk-lista
  (pitch-detektorok polifonikus bemeneten gyakran instabilan, de nem
  feltétlenül SZÉLES szórással viselkednek — pl. egy erős felharmonikuson
  „megülhetnek"). Ez a kör explicit kockázata (OD-01: „a V1 NEM végez
  polifónia-detektálást", proxy-alapú), és a brief pont ezért nevezte meg a
  konkrét fixture-típust — ezt a tesztkör jelenleg nem méri.
- **Kötelező javítás:** legalább egy teszt szintetizáljon 4, egyidejűleg
  összekevert szinusz-hullámot (pl. egy dúr akkord alaphangjai) valódi audio-
  mintaként, futtassa át a valódi `PitchFrameExtractor`-en, és bizonyítsa a
  `unavailable`/`polyphonicInput` kimenetet + hívásszámláló==0-t azon a
  láncon.
- **Ellenőrzés:** az új teszt bukjon, ha a spread-küszöb (vagy az azt
  helyettesítő valódi polifónia-jelző) hiányzik/hibás.
- **Státusz:** **FIXED** (`26f38dd6`). Javítás: ÚJ teszt
  (`'four simultaneous sine chord is unavailable before metric calculation'`)
  — egy `_fourVoiceChord()` helper 4, EGYIDEJŰLEG összekevert szinusz-hullámot
  generál (110/138.591/164.814/220 Hz, A-dúr akkord: A-C#-E-A), 0.2 s-onként
  forgó domináns hanggal (valódi YIN-instabilitást imitálva), a valódi
  `PitchFrameExtractor`-en átfuttatva. Bizonyítja: `status=unavailable`,
  `reason=polyphonicInput`, `metricCalls==0`. Beépített negatív kontroll is
  van a tesztben: ugyanazon frame-eken egy `maximumPitchSpreadCents:
  double.maxFinite` gate-tel `available`-t kapunk — ez igazolja, hogy az
  elutasítás oka valóban a spread, nem egy másik feltétel. **Újra-ellenőrizve**
  (saját, külső mutáció: a spread-ellenőrzés kikapcsolása
  `if (false && spread > …)`): az új teszt PIROSRA vált (`unavailable` várt,
  `available` kapott), a többi 10 teszt zöld marad. Mutáció visszaállítva,
  `git diff --stat` üres.

### F4 — MINOR — A csend-fixture a kapu-szintű kimenetet nem bizonyítja

- **Fájl:** `test/features/audio_analysis/engine/pitch_frame_extractor_test.dart:29-36`
- **Probléma:** a „silence yields only unvoiced frames" teszt csak a
  `PitchFrameExtractor` kimenetét ellenőrzi (minden frame unvoiced), a
  `PitchCapabilityGate`-et sosem hívja. A brief §6 „Csend és zaj" pontja
  viszont a KAPU `unavailable`+dokumentált-ok kimenetét kéri, ahogy a zaj-
  esetnél helyesen meg is történik (60. sor körül, ugyanebben a fájlban).
- **Saját, eldobható próbateszt (elvégezve, visszaállítva):** ideiglenesen
  hozzáadtam egy tesztet, amely a csend-frame-eket ténylegesen átvezeti a
  `PitchCapabilityGate.evaluate`-en. Eredmény: **zöld**,
  `status=unavailable`, `reason=insufficientEvents` — a mögöttes VISELKEDÉS
  helyes (a `voiced.isEmpty` ág, `pitch_capability_gate.dart:84-90`, ezt a
  forráskód olvasásából is megerősíthetően garantálja). A próbatesztet
  eltávolítottam, `git diff --stat` üres.
- **Hatás:** funkcionális hiba NINCS (a próba ezt igazolja), de a kör SAJÁT
  suite-ja nem bizonyítja a brief által név szerint kért kapu-szintű
  kimenetet csendre — csak a zajra.
- **Kötelező javítás:** a meglévő „silence…" tesztet egészítse ki (vagy egy
  új teszt) a `PitchCapabilityGate.evaluate` hívásával és a
  `status`/`reason` explicit ellenőrzésével, ugyanabban a mintában, mint a
  zaj-teszt.
- **Ellenőrzés:** az új assertion bukjon, ha a `voiced.isEmpty` ág eltávolodik
  az `insufficientEvents`-től.
- **Státusz:** **FIXED** (`26f38dd6`). Javítás pontosan a kért mintában: a
  meglévő „silence yields only unvoiced frames" teszt kiegészült a
  `PitchCapabilityGate.evaluate` hívásával, `expect(capability.status,
  CapabilityStatus.unavailable)` és `expect(capability.reason,
  CapabilityUnavailableReason.insufficientEvents)` explicit ellenőrzéssel.
  Diff-fel megerősítve, a gate-futásban zöld.

### F5 — MINOR — A voiced-arány küszöb-hármas dokumentálatlanul tér el a brief szó szerinti celláitól

- **Fájl:** `test/features/audio_analysis/engine/pitch_capability_gate_test.dart:23-37`
- **Probléma:** a brief §6 explicit 0.349/0.350/0.351 cellákat kér
  (`200 frame` mellett ez 69.8/70.0/70.2 — tört frame-szám, tehát szó szerint
  konstruálhatatlan). A teszt emiatt (érthető okból) 69/70/71-et használ
  (0.345/0.350/0.355), DE a brief explicit kéri: „a pontos konstrukciót a
  teszt dokumentálja" — ez a dokumentáció (komment, miért 69/70/71 és nem pl.
  egy más totál-frame-szám, ami közelebb esne a névleges 0.349/0.351-hez)
  HIÁNYZIK a tesztfájlból.
- **Hatás:** a viselkedés funkcionálisan helyes (a pontosan 0.350
  inkluzivitása bizonyított), csak a nyomon-követhetőség hiányos —
  egy jövőbeli olvasó nem tudja megkülönböztetni „szándékos, dokumentált
  közelítés" és „elgépelt/hibás küszöb-cella" között.
- **Kötelező javítás:** egysoros komment a fixture fölé, ami rögzíti: miért
  69/70/71 és nem a névleges 0.349/0.350/0.351 (a tört frame-szám okát és a
  választott közelítés indoklását).
- **Ellenőrzés:** dokumentáció-jellegű, nincs teszt-következménye.
- **Státusz:** **FIXED** (`26f38dd6`). Pontosan a kért egysoros komment
  került a fixture fölé: „0.349 and 0.351 need fractional voiced frames out
  of 200; 69/70/71 preserve the below/at/above observation and prove 0.350
  is inclusive." Diff-fel megerősítve.

### F6 — NOTE — A §10 handoff nem dokumentálja a mérce-mátrix saját maga kérte valódi-sértés próbát

- **Fájl:** `docs/rounds/e06-r17-monophonic-pitch-capability.md` §10
- **Probléma:** a brief §6.1 mérce-mátrixának utolsó sora explicit kéri:
  „Valódi-sértés próba (§10): a polifónia-kapu ideiglenes kiszedése → a
  négyhangos akkord unavailable cella PIROS → visszaállítás." A §10 handoff,
  ahogy az implementer kitöltötte, ezt nem említi (sem az elvégzését, sem az
  eredményét).
- **Hatás:** nem tudható a jelentésből, hogy az implementer elvégezte-e ezt
  önállóan; a review oldalán most pótlólag megtörtént (F3 alatt
  dokumentálva), de ez a REVIEWER munkája volt, nem az implementeré, ahogy a
  mérce-mátrix eredetileg szánta.
- **Kötelező javítás:** nem blokkoló; jövőbeli körökben a §10 kitöltésekor a
  mérce-mátrix saját-próba sorait explicit pipálja/dokumentálja az
  implementer.
- **Státusz:** OPEN (follow-up jellegű, nem blokkol). A javító kör (`26f38dd6`)
  csak `test/**`-et érintett, a `docs/rounds/**` §10 nem változott — ez
  továbbra is nyitva marad, de a mérce-mátrix által kért próbákat a review
  (F1/F3 alatt) és a fix commit tesztjei (F1/F3 új tesztjei) is elvégzik, úgy
  hogy a tényleges regresszióvédelem MOST megvan, csak a §10 dokumentáció
  hiányzik.

### F7 — NOTE — ARB-beszúrás egy másik kulcs kulcs/metaadat párja közé ékelődik

- **Fájlok:** `lib/l10n/app_en.arb`, `lib/l10n/app_hu.arb`
- **Probléma:** a 7 új `pitchMetric*` kulcs a `"aiTutorEvidenceMetric"` érték-
  sora ÉS a saját `"@aiTutorEvidenceMetric"` metaadat-sora KÖZÉ van beszúrva,
  nem egy logikailag összefüggő helyre (pl. a fájl végére, vagy egy meglévő
  pitch/tuner-blokk mellé). Funkcionális hatása nincs (egyik új kulcsnak sincs
  placeholdere, az l10n parity gate zöld), csak olvashatósági/diff-tisztasági
  nit.
- **Státusz:** OPEN (kozmetikai, nem blokkol). A javító kör nem érintett ARB
  fájlt (csak `test/**`) — változatlanul nyitva, de nem blokkoló follow-up.

## Gate-bizonyíték

### Első kör (`2c02f031`, izolált `/tmp/review-e06-r17` klón)

Mind a négy célzott teszt-útvonal + a gate script beépített lépései, saját
kézzel, **elölről**, izolált `/tmp/review-e06-r17` klónban (a `2c02f031`-gyel
tartalmilag azonos, SHA-ellenőrzött forrásfa), `--result-json` strukturált
kimenettel:

| Gate | Állított eredmény (implementer §10) | Saját, független futtatás |
|---|---|---|
| format | zöld | ✅ zöld |
| analyze | zöld | ✅ zöld (0 issue) |
| test test/features/audio_analysis | zöld | ✅ zöld — **320/320** teszt |
| test test/property | zöld | ✅ zöld — **86/86** teszt, `PROPERTY_SEED=42` |
| test test/core | zöld | ✅ zöld — **401/401** teszt |
| test test/features/tuner | zöld | ✅ zöld — **42/42** teszt, érintetlen fájlokkal |
| architecture | zöld | ✅ zöld — 12 előzetes (más körökből származó) allowlisted deviation, ÚJ eltérés nincs |
| secrets | (nem hivatkozott) | ✅ zöld — 2308 fájl, 0 találat |
| l10n parity | (nem hivatkozott) | ✅ zöld — en→hu, 1051 üzenet |

Strukturált eredmény (`ROUND_GATE_RESULT_FILE`):
`{"command_exit_code": 0, "error_hash": null, "exit_code": 0, "failed_step":
null, "outcome": "pass", "schema_version": 1}`

Az implementer §10 „célzott flutter test (20 teszt)" állítása pontos: a 4 új
pitch-tesztfájl összesen 4+11+4+1=20 tesztet regisztrál.

A 4513 ms-os (30 s-os A4 klip) mért futásidő a brief §9 saját kockázat-
bejegyzése szerint **előre jóváhagyott, nem-blokkoló** follow-up (E06-R29) —
nem defekt, a brief kifejezetten ezt írja elő 3 s fölötti mérésre.

### Javító kör (`26f38dd6`, ÚJ izolált `/tmp/review-e06-r17-fix1` klón)

A gate-et **friss** izolált klónban, elölről, GitHubról közvetlenül fetchelt
(`26f38dd6`-ra ellenőrzött) forrásfán futtattam újra — a korábbi
`/tmp/review-e06-r17` klónt NEM használtam fel:

| Gate | Saját, független futtatás (javító kör) |
|---|---|
| format | ✅ zöld |
| analyze | ✅ zöld (0 issue) |
| test test/features/audio_analysis | ✅ zöld — **322/322** teszt (+2 az F1/F3 új tesztjei miatt) |
| test test/property | ✅ zöld — **86/86** teszt, `PROPERTY_SEED=42` |
| test test/core | ✅ zöld — **401/401** teszt (változatlan) |
| test test/features/tuner | ✅ zöld — **42/42** teszt (változatlan, érintetlen fájlokkal) |
| architecture | ✅ zöld — 12 allowlisted deviation, ÚJ eltérés nincs |
| secrets | ✅ zöld — 2310 fájl, 0 találat |
| l10n parity | ✅ zöld — en→hu, 1051 üzenet |

Strukturált eredmény: `{"command_exit_code": 0, "error_hash": null,
"exit_code": 0, "failed_step": null, "outcome": "pass", "schema_version": 1}`

## Mutáció-próbák — első kör (mind eldobva, visszaállítva)

| # | Cél | Módszer | Eredmény |
|---|---|---|---|
| 1a | Flag-kapu sorrend (relokáció) | flag-check az `available` elé mozgatva | Mind a 4 dedikált teszt ZÖLD marad → konfundált fixture |
| 1b | Flag-kapu (teljes törlés) | `if (!analysisPitchEnabled && false)` | Csak `pitch_metrics_test.dart` 1 tesztje PIROS; a dedikált fájl végig zöld |
| 2 | Polifónia call-counter | spread-ellenőrzés `if (false && …)` | 2 teszt PIROS (gate + metrics fájl) — a kapu-logika védett |
| 3 | NaN-mentesség property valódisága | `centsBetween()` → feltétel nélkül `double.nan` | Property teszt ZÖLD marad; 9/11 fixture-teszt PIROS (`ArgumentError`) |
| 4 | Csend → kapu (megerősítés, nem sértés) | ideiglenes teszt hozzáadva, a gate-et hívva | ZÖLD, `unavailable`/`insufficientEvents` — viselkedés helyes, csak lefedetlen |

## Mutáció-próbák — javító kör után, MEGISMÉTELVE (mind eldobva, visszaállítva)

Ugyanazok a mutációk, ugyanazokon a produkciós fájlokon, az ÚJ izolált
`/tmp/review-e06-r17-fix1` klónban, a `26f38dd6`-beli JAVÍTOTT tesztek ellen:

| # | Cél | Módszer | Eredmény (javító kör előtt → után) |
|---|---|---|---|
| 1a | Flag-kapu sorrend (relokáció) | ugyanaz | ZÖLD marad → **`'flag OFF precedes…'` (ÚJ teszt) PIROS** |
| 1b | Flag-kapu (teljes törlés) | ugyanaz | csak metrics-teszt PIROS → **MINDKÉT releváns gate-teszt PIROS** |
| 2 | Polifónia call-counter (4-hangos akkord) | ugyanaz a spread-kikapcsolás | (nem volt 4-hangos fixture) → **`'four simultaneous sine chord…'` (ÚJ teszt) PIROS** |
| 3 | NaN-mentesség property valódisága | ugyanaz a `centsBetween → double.nan` | ZÖLD marad → **azonnal PIROS**, ugyanaz az `ArgumentError` mint a fixture-teszteknél |

Minden mutáció visszaállítva mentett eredetiből; a végső `git status --short`
és `git diff --stat github/codex/e06-r17-monophonic-pitch-capability` (a
javító commithoz képest) üres mindkét körben — a review egyik körben sem
hagyott produkciós-kód változást.

## Merge-döntés

### Első kör: CHANGES REQUESTED (lezárva)

A gate teljesen zöld és a scope-audit tiszta volt, de az ADR 0052 zöld-kapu
ÖNMAGÁBAN nem volt elég: 3 nyitott MAJOR állt fenn (F1-F3), mindegyik
„hiányzó teszt a viselkedésváltozásra/garanciára" kategóriában — a kör
legkritikusabb, névvel nevezett, részben kétszeres pre-flight-kört is kapott
garanciáin (flag-kapu sorrend, NaN-mentesség, polifónia-fixture hűsége). A
produkciós kód ELLENŐRIZVE helyesen viselkedett mindhárom esetben — a hiány
kizárólag a REGRESSZIÓVÉDELEM oldalán volt.

### Javító kör után: **APPROVED**

A `26f38dd6` javító commit mind az 5 nyitott leletet (F1-F5) lezárta, saját
kézzel, ÚJ izolált klónban, a jelentés által előre rögzített pontos mutáció-
próbákkal megismételve ellenőrizve — egyik esetben sem az implementer
állítására hagyatkozva. BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 2 (F6/F7,
nem blokkoló follow-up, a kör kifejezetten nem érintette őket). A gate
teljesen zöld egy FRISS, GitHubról közvetlenül fetchelt klónban; a scope-
audit tiszta (3 fájl, mind `test/**`, 0 produkciós-kód sor); a Tuner-paritás
és a tilos zóna továbbra is érintetlen. A párhuzamos, független security
review is PASS (0 CRITICAL/BLOCKER/MAJOR).

Az ADR 0052 szerint: minden gate zöld ÉS nincs nyitott BLOCKER/MAJOR →
merge-elhető. A teljes CI suite + randomizált property gate + APK build
(ADR 0053) ezen a `26f38dd6` exact SHA-n még szükséges az orchestrátor
oldalán a tényleges merge előtt — ezt a reviewer nem futtatja (AGENTS.md §12).

### Folyamat-megjegyzés (nem blokkol, informatív)

Az első körben talált push-hiányosságot (a `2c02f031` nem volt fent
originon) az azóta lezajlott pipeline-lépések (security review push, javító
kör push) maguktól feloldották — a `26f38dd6` már a valódi GitHub `origin`-on
van, ahogy ezt a jelen javító-kör review is közvetlenül, a GitHub remote-ból
fetchelve ellenőrizte.
