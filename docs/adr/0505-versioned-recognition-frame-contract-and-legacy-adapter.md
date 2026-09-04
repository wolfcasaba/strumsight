# ADR 0505 — Verziózott felismerési szerződés: a bizonytalanság típusos, a kalibrálatlan valószínűség nem confidence, a legacy fordítás adapterben él

- **Státusz:** elfogadva
- **Dátum:** 2026-09-04
- **Kör:** `E14-R04` (Chapter 14 — Recognition Accuracy & Useful UI Recovery, Kör 4)
- **Kapcsolódó:** [`0271`](0271-recognition-recovery-program.md) §1
  (`UNKNOWN > CONFIDENTLY WRONG`),
  [`0216`](0216-analysis-confidence-calibration-and-abstention.md)
  (kalibrálatlan valószínűség nem közölhető confidence-ként),
  [`0116`](0116-legacy-song-setlist-migration-boundary.md)
  (legacy adapter: a fordítás lokális típusban él),
  [`0293`](0293-legacy-evidence-adapter-identity-and-mapping-contract.md)
  (a domain nem igazodik a legacy hiányaihoz),
  [`0002`](0002-feature-first-clean-architecture.md) (architecture guard),
  [`0355`](0355-fail-visible-model-activation-telemetry.md)
  (`RecognitionRuntimeInfo`, amit ez a szerződés HORDOZ, nem ír újra)
- **Előzmény:** `docs/LESSONS.md` L619 (a kézzel írt séma-validátor
  alapértelmezésben fail-OPEN), L05/L09 (a gate artefaktum, nem parancssor)

## Kontextus

A Live felismerő út ma **bináris**, és **egyetlen** confidence-t közöl — azt is a
strumét. Mért állapot a `main @ f7fd7ab0` fán:

- `lib/features/live/model/live_frame.dart` — 108 sor, 11 mező; az egyetlen
  közölt bizonyosság `double get confidence => latestStrum?.confidence ?? 0;`
  (`:70`). Az **akkordnak nincs saját közölt confidence-e**.
- `lib/features/live/engine/dsp/live_pipeline.dart:233-236` —
  `showChord = _lastChord != null && _chordLatched`. Ha a latch nem áll be, a UI
  **semmit** nem lát: „bizonytalan" állapot a szerződésben nem létezik.
- **22 fájl** hivatkozik a `LiveFrame`-re (`lib/` + `test/`, mérve
  `grep -rl "LiveFrame" lib/ test/ | wc -l`) — köztük a `live_screen.dart`, a
  `live_status_bar.dart`, a `chord_timeline_provider.dart` és a
  `live_practice_observation_gateway.dart`.
- `lib/features/live/domain/` **nem létezik**; a feature ma `model/`, `engine/`,
  `providers/`, `screens/`, `widgets/` mappákat használ.

Ebből az következik, hogy az `ADR 0271` §1 követelménye — a bizonytalanság
MEGJELENÍTÉSE — a jelenlegi szerződésben **nem kifejezhető**: a UI-nak nincs mit
megjelenítenie, mert a frame vagy tud egy akkordot, vagy nem tud semmit. A
Chapter 14 hátralévő körei (R05 jelminőség, R11 akkord-bizonytalanság, R12
stabilizátor, R13 UI-igazmondás) mind erre a hiányzó szerződésre épülnek.

Ez a kör **szerződést ad, nem UI-t**, és **nem hangol felismerést**.

## Döntés

### D1. A felismerési szerződés Flutter-független domain rétegben él

`lib/features/live/domain/recognition/**` egyetlen fájlja sem importálhat
`package:flutter/*`, `package:flutter_riverpod/*` vagy `package:riverpod/*`
könyvtárat. Az őr **gépi**, és a fa bevett mintáját követi: önálló,
forrás-szkennelő csoport a `test/core/architecture_dependency_test.dart`-ban,
pontosan úgy, ahogy a `practice_generator/domain` (`:23`), a
`gamification/domain` (`:101`) és a `community/domain` (`:982`) csoportja.

**A `tool/check_architecture.dart` NEM módosul.** Mérve: az ottani
`_isSharedDomain` (`:419-422`) három prefixet drótoz be, és a
`checkArchitecture` nem kínál bővítési pontot — a feature-domainek őrei ezért
élnek eleve a tesztben. A `tool/` ennek a körnek a **tilos zónája**.

**`package:meta/meta.dart` MEGENGEDETT.** A `@immutable` innen jön, nem a
`package:flutter/foundation.dart`-ból: így csinálja a `lib/core/music/chord.dart`
(`:1`) és maga a `lib/features/live/model/recognition_runtime_info.dart` (`:1`)
is, és a `_isForbiddenDomainDependency` (`:424-437`) sem tiltja. A domain
osztályok `const` konstruktorral és `final` mezőkkel immutable-ök.

### D2. A kalibrálatlan valószínűség NEM confidence

`pDown` / `pUp` / `pNoStrum` / `pNoChord` / `pUnknown` **nyers modell-kimenet**.
A `calibratedConfidence` **nullable**, és `null` marad addig, amíg nincs MÉRT
kalibráció — a kalibráció külön kör tárgya.

A nyers valószínűség „ideiglenes" átmásolása a `calibratedConfidence`-be
**tilos**: pontosan ez az a hazugság, ami ellen az `ADR 0216` és az `SDD Ch14
§9.6` szól. Egy `null` confidence azt jelenti, hogy *nem tudjuk* — és ez több
információ, mint egy kitalált szám.

### D3. A `decision` a jóslaté, nem a UI-é

`RecognitionDecision` zárt enum: `candidate`, `provisional`, `confirmed`,
`uncertain`, `rejected`, `expired`; az elutasítás okát a szintén zárt
`RecognitionRejectReason` hordozza (`lowConfidence`, `unstable`,
`signalQuality`, `noChord`, `modelUnavailable`, `timeout`).

Az állapot a **domainben** dől el, és a widget-réteg CSAK megjeleníti. Küszöböt
a widget-rétegben kiértékelni tilos.

**Ebben a körben egyetlen levezetés szerződéses:** az irány-döntés a
`directionMargin`-ból. `ChordPrediction.decision` és `SignalQualitySnapshot`
ebben a körben **konstruktorból kapott** érték — akkord-döntést levezetni MÉRT
kalibráció nélkül az a hiba lenne, amit a D2 tilt; azt az `E14-R05` (jelminőség)
és az `E14-R11` (akkord-bizonytalanság) hozza. A D3 így is teljesül: a döntés a
jóslaton ül, sosem a widgetben.

### D4. A `directionMargin` SZÁMÍTOTT, nem tárolt

`double get directionMargin => (pDown - pUp).abs();`

Konstruktor-paraméterként a szerződés **inkonzisztens állapotot engedne
megépíteni** (`pDown: 0.9, pUp: 0.1, directionMargin: 0.01`), amitől a küszöb-
táblázat mérése értelmét vesztené. Getterként a margó és a valószínűségek nem
csúszhatnak szét.

**A küszöb `0.05`, és az elutasítás oldalán INKLUZÍV** (`margin <= 0.05` →
`uncertain`, `RecognitionRejectReason.lowConfidence`). Ez a szerződés
**alapértéke**, nem hangolt DSP-paraméter: a domain konstansként hordozza, és a
későbbi, MÉRT kalibrációs kör írja felül ADR-rel. Küszöbhangolás ebben a körben
TILOS (AGENTS.md §9).

### D5. Az adapter fordít, nem dönt

A `LiveFrameAdapter` a régi `LiveFrame`-et állítja elő, hogy a **22 hívó
érintetlen** maradjon (`ADR 0116` mintája). Az `uncertain` / `provisional` /
`candidate` / `rejected` / `expired` állapotot `confirmed`-ként átfordítani —
„hogy legyen mit mutatni" — tilos: a régi frame ilyenkor `current: null`, ami
PONTOSAN a mai `_chordLatched == false` viselkedés. A kompatibilitás nem ronthat
a mai igazságtartalmon, és nem is javíthat rajta némán.

**Az adapter az EGYETLEN dokumentált legacy-határ a domainben.** Mérve: a
`lib/features/live/model/live_frame.dart:1` `package:flutter/foundation.dart`-ot
importál, az adapternek viszont `LiveFrame`-et kell építenie. A D1 őre ezért a
`domain/recognition/**` **közvetlen** import-direktíváit méri; az adapter
`import '../../model/live_frame.dart';` sora legális. A másik öt, tisztán
szerződés-fájl a `model/`-ből semmit nem importálhat a
`recognition_runtime_info.dart`-on kívül (az `package:meta`-n áll,
`ADR 0355`) — ezt külön cella pinneli.

### D6. A szerződés verziózott, és a parse fail-CLOSED

`RecognitionFrame.schemaVersion` konstans (`1`). Ismeretlen verzió esetén a
`fromJson` **típusos hibát dob** — nem ad `null`-t, és nem olvas „legjobb tudása
szerint" részleges objektumot.

Ugyanez a szigor kötelező **minden** `fromJson`-re: hiányzó kötelező kulcs
típusos hiba, nem csendes `null`. Ez a `docs/LESSONS.md` **L619** (E14-R02,
ugyanez a fejezet) mért hibaosztálya: *a kézzel írt validátor
alapértelmezésben fail-OPEN — a le nem fedett kulcs nem hibás, hanem nem
létezik, és a séma szigorúbbnak LÁTSZIK, mint amit érvényesít.* Ezért a
boldog-utas round-trip önmagában NEM elég bizonyíték: modellenként kell egy
hiányzó-kulcs cella is.

## Következmények

- A Live UI a következő körökben meg tudja különböztetni a biztos, a
  bizonytalan, az ideiglenes és az elutasított felismerést, és külön látja az
  akkord- és az irány-confidence-t.
- A `LiveFrame` **bájtra változatlan** marad; a 22 hívó nem módosul. A régi
  `LiveFrame.confidence` továbbra is a strum értékét adja.
- A `domain/` mappa bevezetése a `live` feature-be **konvergencia**, nem új
  konvenció: az `audio_analysis`, a `gamification`, a `community` és a
  `practice_generator` már így épül.
- A `lib/features/live/public.dart` **kézzel írt** barrel (mérve: csak a
  `practice_generator` rendelkezik `public/` fragmentumokkal), tehát additív
  exporttal bővül, generátor nélkül.
- A `null` `calibratedConfidence` a hívóknak munkát ad: a UI-nak kezelnie kell a
  „nem tudjuk" esetet. Ez szándékos — az `ADR 0271` §1 épp ezt követeli.
- Az élő csővezeték átkötése az új szerződésre **nem** ebben a körben történik;
  a `live_pipeline.dart` és az engine-fájlok érintetlenek.

## Alternatívák

- **A `LiveFrame` bővítése új mezőkkel.** Elvetve: 22 hívót érintene, és a
  `model/` réteg Flutter-függő marad (`flutter/foundation.dart`), tehát a
  szerződés nem lenne tesztelhető keretrendszer nélkül.
- **A `calibratedConfidence` nem-nullable, `0.0` alapértékkel.** Elvetve: a
  `0.0` megkülönböztethetetlen a mért „biztosan nem" értéktől — pontosan a D2
  tiltotta hazugság, csak más köntösben.
- **A `decision` kiszámítása a UI-ban.** Elvetve: minden képernyő újra
  kitalálná a küszöböket, és a `ADR 0271` §1 követelménye nem lenne gépi
  mércével mérhető.
