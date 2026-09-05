# ADR 0516 — A chord-döntés BEKÖTÉSE: a szállított akkord-kapu a MÁR MERGE-ELT `RecognitionDecision`-be kerül, második szótár nélkül

- **Státusz:** Elfogadva
- **Kör:** `E14-R11` (Chapter 14 — Recognition Accuracy & Useful UI Recovery, Kör 11)
- **Dátum:** 2026-09-05
- **Implementer motor:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Kapcsolódó:**
  [ADR 0505](0505-versioned-recognition-frame-contract-and-legacy-adapter.md)
  (a szerződés, amit ez a kör az AKKORD-oldalon beköt: `ChordPrediction`,
  `RecognitionDecision`, `RecognitionRejectReason`; a `ChordPrediction`
  osztály-doksija NÉVSZERINT ezt a kört nevezi meg a levezetés helyeként),
  [ADR 0512](0512-live-direction-abstention-wiring.md)
  (a STRUM-oldal ugyanezen bekötése — ez az ADR annak az akkord-ikertestvére,
  és szándékosan ugyanazt az alakot követi),
  [ADR 0271](0271-recognition-recovery-program.md)
  (`UNKNOWN > CONFIDENTLY WRONG`; nevesíti a gyökérokot: „a `LiveFrame` túl
  kevés információt visz a UI-nak ahhoz, hogy a bizonytalanság
  megjeleníthető legyen"),
  [ADR 0507](0507-live-signal-quality-analyzer-reuse-route-and-hysteresis.md)
  (`SignalQualityState` — a jel-minőség MÁR MEGHOZOTT döntése)

## Kontextus — a pre-flight MÉRT tényei (2026-09-05, `main @ 744797b8`)

Az előre megírt brief (2026-08-20, `main @ 88e08e65`) óta a fa elmozdult; a
`brief-lint` **S15** lelete emiatt keletkezett. A pre-flight újramérése négy
tényt talált, és mind a négy megváltoztatja a kör tartalmát.

### 1. Az akkord-bizonytalanság szótára MÁR MERGE-ELVE VAN

A brief §5.4 három ÚJ állapotot írt elő a frame-ben (`noChord`,
`unknownChord`, `lowSignal`). A fában viszont már él a teljes, merge-elt
szótár:

- `RecognitionDecision` — `candidate`, `provisional`, `confirmed`,
  `uncertain`, `rejected`, `expired`
  (`lib/features/live/domain/recognition/recognition_decision.dart:5-23`);
- `RecognitionRejectReason` — `lowConfidence`, `unstable`, `signalQuality`,
  `noChord`, `modelUnavailable`, `timeout` (uo. `:43-49`).

A brief három állapota maradék nélkül leképződik erre: `noChord` →
`RecognitionRejectReason.noChord`, `unknownChord` → `lowConfidence`,
`lowSignal` → `signalQuality`. Egy ÚJ enum tehát **második, divergens
szótár** volna ugyanarra a döntésre — pontosan az a hibaosztály, amit az
E14-R10 H3-ja és a [L636](../LESSONS.md#l636) mért.

### 2. A külön chord/strum confidence MÁR MERGE-ELT szerződés

A brief §5.1 két külön `LiveFrame`-mezőt írt elő. A `RecognitionFrame`
osztály-doksija (`recognition_frame.dart:8-13`) viszont szó szerint ezt
mondja ki: „the chord- and direction-confidence are carried SEPARATELY
([chord]/[strum])". A szétválasztás tehát nem ennek a körnek a döntése,
hanem az ADR 0505-é — ez a kör **beköti**, nem újra kimondja.

### 3. Az akkord-döntésnek MA NINCS termelője

`grep -rn "ChordPrediction(" lib/` → a saját konstruktoron és a
`fromJson`-on kívül **nulla** találat. A `live_pipeline.dart` a
`_chordLatched` bool-lal dönt, és a frame-be nyers `Chord`-ot vagy `null`-t
tesz (`live_pipeline.dart:338-341`). A `ChordPrediction.decision` ezért ma
konstruktor-kapott — az osztály doksija (`chord_prediction.dart:7-10`)
kimondja, hogy a levezetés „ships in `E14-R05`/`E14-R11`". Az E14-R05 a
jel-minőséget szállította; a levezetés tehát ENNEK a körnek a dolga.

### 4. A brief UI-céljai HALOTT KÓDRA mutatnak — ez a kör hatókörén KÍVÜL esik

Mérve (`grep -rn "chord_display.dart\|confidence_pill.dart" --include=*.dart .`):

- `lib/features/live/widgets/confidence_pill.dart` és
  `lib/features/live/widgets/chord_display.dart` importőrei: **kizárólag**
  `test/features/live/live_widgets_test.dart`. A `lib/` fában **nulla**
  használó.
- A SZÁLLÍTOTT Live felület a `live_screen.dart` → `SsChordHero` úton
  rajzol, és ott írja ki a kalibrálatlan százalékot
  (`live_screen.dart:350`), valamint a `chord_timeline_card.dart:225`-ben.

Vagyis a brief §1 célja („a UI ne mutasson akkordnevet bizonytalanságnál",
„százalék helyett szöveges állapot") a felsorolt fájlok átírásával
**nem teljesülne** — két nem-renderelt widget változna, a felhasználó
ugyanazt látná. A tényleges javítás a `lib/features/live/screens/**`-ot
kívánná, amit a brief maga sorol a TILOS zónába; a lista tágítása az
orchestrátornak nem hatásköre (ADR 0087 §2 H3). Ez a kör ezért a
**domain-felet** szállítja, és a UI-felet nevesítetten továbbadja.

Másodlagos mérés ugyanide: `live_widgets_test.dart:50` a
`find.textContaining('94%')` cellával **kipinneli** a pill százalékát, és
a fájl a brief listáján kívül van — a brief §5.2 változtatása tehát egy
nem engedélyezett fájlt vinne pirosra (S14-osztály).

### 5. Az előre kiosztott `0363` szám elavult

`docs/adr/0363-*.md` nem létezik, a legmagasabb szám `0512`, és a foglaló
(`tools/round-slots.py reserve-adr --round E14-R11`) a **`0516`** számot
adta. Ugyanaz a mintázat, mint az E14-R10-nél (`0362` → `0512`) és az
E14-R09-nél (`0361` → `0511`): a 2026-08-20-i előre írt briefek ADR-számai
tárgytalanok. A foglaló `O_CREAT|O_EXCL` markert ír, ezért ő a mérvadó
(`tools/tests/test_adr_numbering.py`).

## Döntés (NEM tárgyalható — a kör kötött szabályai)

### D1 — Egyetlen döntési hely: a `live_pipeline.dart`

Az akkord-verdikt tipizálása KIZÁRÓLAG a `live_pipeline.dart`-ban
történik, pontosan úgy, ahogy az ADR 0512 az irányt kötötte be
(`_isDirectionConfirmed`). A kör **nem** hoz létre új enumot, új
állapotnevet vagy új küszöböt: a merge-elt `RecognitionDecision` /
`RecognitionRejectReason` értékeit használja.

### D2 — A `calibratedConfidence` marad `null`

Nincs mért akkord-kalibráció a fában (a
`evaluation/recognition/baseline_manifest.json` a kalibrációt
`not-measured`-ként jelöli). Egy szám beírása a `calibratedConfidence`-be
pontosan az a hazugság, amit az ADR 0505 D2 tilt. A kör tehát a
**döntést** vezeti le, a **számot** nem — ugyanaz a szétválasztás, amit az
ADR 0512 a strumnál alkalmazott.

### D3 — A döntés a MÁR SZÁLLÍTOTT kapuból jön, nem új küszöbből

A levezetés bemenete a ma is futó Schmitt-kapu
(`chordConfRise = 0.54`, `chordConfRelease = 0.22`,
`chordConfEmaAlpha = 0.35`, `DspConfig`) és a tonalness-kapu
(`chordMinTonalness = 0.7`). A kör **egyetlen** küszöböt sem hangol és
egyet sem duplikál — a kapu marad a `DspConfig` egyetlen helyén.

**Inkluzivitás (kimondva, hogy ne driftelhessen):** a rise-oldal
**megerősítés-oldalon inkluzív** (`_chordConfEma >= _chordConfRise` →
latch), mert a szállított kód ma ezt teszi. Ez SZÁNDÉKOSAN más
konvenció, mint az ADR 0505 `uncertainMarginThreshold`-ja, amely
elutasítás-oldalon inkluzív (`margin <= 0.05` → `uncertain`). A két
küszöb két külön jelenséget mér; az eltérést itt rögzítjük, hogy egy
későbbi kör ne „egységesítse" némán, viselkedést változtatva.

### D4 — Az elutasítási ok gépi leképezése

A `rejectReason` a `decision`-nal EGYÜTT keletkezik (soha nem külön
tárolt, driftelhető mező), és a merge-elt jel-minőség-döntést tiszteli:

| Mért helyzet | `decision` | `rejectReason` |
|---|---|---|
| a kapu latch-elt (`_chordLatched`), van akkord | `confirmed` | `null` |
| a jel-minőség nem `good`/`unknown` (ADR 0507) | `rejected` | `signalQuality` |
| tonalness-kapuzott / nincs akkord-match | `rejected` | `noChord` |
| van match, de a kapu alatt van | `uncertain` | `lowConfidence` |

A jel-minőség ELŐBB dönt, mint a kapu: ha a `SignalQualityState` szerint a
bemenet nem használható, az ok `signalQuality`, nem `lowConfidence` — a
felhasználónak megmondható, hogy a mikrofon a probléma, nem a fogása.

### D5 — A `LiveFrame` additívan viszi a TIPIZÁLT döntést, számot nem

Az ADR 0271 nevesített gyökéroka a „`LiveFrame` túl kevés információt
visz". A kör ezért additív, alapértelmezett értékű mezőkkel bővíti:
`chordDecision` (`RecognitionDecision?`) és `chordRejectReason`
(`RecognitionRejectReason?`). **NEM elfogadható** egy nyers
`chordConfidence` double a frame-en: az a D2-tiltott kalibrálatlan szám
lenne confidence alakú mezőben.

A meglévő `LiveFrame.confidence` getter (a STRUM confidence-e) marad,
doksi-pontosítással — törlés nincs, a 19+ hívó fordul tovább.

### D6 — A UI-fél NEM ebben a körben van

A szöveges állapot megjelenítése és a kalibrálatlan százalék eltüntetése a
`live_screen.dart` / `chord_timeline_card.dart` úton történhet, ami ennek a
körnek a tilos zónája (§4. mérés). Ez a kör tehát **nem** állítja, hogy a
Chapter 14 §9/6 („kalibrálatlan valószínűséget tilos százalékként mutatni")
teljesült. Az a javítás egy külön kör dolga, amelynek `allowed_paths`-a a
`lib/features/live/screens/live_screen.dart`-ot és a
`lib/features/live/widgets/chord_timeline_card.dart`-ot is tartalmazza.

### D7 — Az adapter-út érintetlen marad, és ezt teszt rögzíti

A `live_frame_adapter.dart` a lista KÍVÜL van, ezért az új mezőket nem
tölti — a `LiveFrameAdapter.toLiveFrame` kimenetén az új mezők az
alapértelmezett `null` értéken maradnak. Ez tudatos, nem feledékenység: az
adapter-út bekötése ahhoz a körhöz tartozik, amelyik a pipeline→adapter
átkötést is elvégzi (az adapter saját doksija szerint az „a later round's
job"). A kör tesztje ezt a hézagot **kimondottan pinneli**, hogy ne néma
maradjon.

## Következmények

- A Live pipeline mostantól tipizált, merge-elt szótárú akkord-verdiktet
  ad — a UI-kör bemenete készen áll.
- A felhasználó által LÁTOTT viselkedés ebben a körben **nem változik**:
  a `showChord` kapu ugyanaz marad, a frame `current` mezője ugyanazt
  hordozza. A kör additív; regressziót nem okozhat.
- A Chapter 14 §9/6 UI-adóssága NYITVA marad, nevesítve (D6).
