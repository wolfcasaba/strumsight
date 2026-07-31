# E02-R08 review — Observation gateway és audio lifecycle adapter

- **Kör:** E02-R08 (`docs/rounds/e02-r08-observation-gateway.md`, [ADR 0074](../adr/0074-practice-observation-gateway.md))
- **Branch:** `mm/e02-r08-observation-gateway` @ `ff905fd`
- **Implementer:** MiniMax M3 · **Reviewer:** Claude (Opus 5)
- **Dátum:** 2026-07-31
- **Verdikt (R0, `ff905fd`):** **CHANGES REQUESTED** — 0 BLOCKER · **2 MAJOR** · 1 MINOR · 3 NOTE

## 1. Gate-újrafuttatás (reviewer, izolált klón `/tmp/review-e02r08`)

Mind az öt gate-et magam futtattam, a `tools/round-gate.sh` artefaktummal,
csonkítatlanul:

| Gate | Kimenet |
|---|---|
| `dart format --output=none --set-exit-if-changed lib test tool` | `Formatted 528 files (0 changed)` |
| `flutter analyze lib/ test/ tool/` | `No issues found!` |
| `flutter test test/features/practice/` | `00:27 +437: All tests passed!` |
| `flutter test test/property/practice_observation_property_test.dart` | `00:01 +5: All tests passed!` |
| `dart run tool/check_architecture.dart` | `Architecture dependencies OK (12 allowlisted deviation(s)).` |

**A gate maradéktalanul zöld — és két MAJOR van alatta.** Ez az ötödik egymást
követő kör, ahol ez így áll ([`docs/LESSONS.md`](../LESSONS.md) L01).

## 2. Scope-audit

`git show --stat ff905fd` → **13 fájl**, mind a brief §4 engedélyezett listáján.

Tilos zóna mérten érintetlen (`git diff --stat main...ff905fd -- …` → üres):
`lib/features/learn/**` · `lib/features/live/engine/**` · `lib/core/audio/**` ·
`tool/**`. A `lib/features/live/public.dart` +3 sor (egy export + doc), a
`lib/core/foundation/app_failure.dart` +4 sor pontosan a practice szekcióban,
az `architectureAllowlist` **változatlan** (12 tétel).

`grep -rn 'LivePracticeObservationGateway|practiceCaptureActiveByStatus|PracticeObservationGateway' lib/`
→ practice-en kívül **0 találat**: nincs provider, nincs hívó, a production
viselkedés bitre azonos (§6.10 teljesül).

**Scope: tiszta.** A branch további commitjai (`f293170`, `50837f8`, `13ba224`)
az orchestrátor sajátjai (brief + ADR + chunk 014, brief-revízió R1, valamint az
L12–L13 tanulságok és a `tools/wait-for-round.sh`) — nem az implementer diffje.

## 3. Próbatesztek (eldobható, `zz_reviewer_probe_test.dart`, merge előtt törölve)

Két próba, **két bukás** a 437 zöld teszt és az 5 zöld property mellett. Mindkettő
a **legacy referenciával** szembe mér (`learn_screen.dart` `_onFrame` +
`_scorer.observeChord`), nem szemrevételezés:

| Próba | Elvárt (legacy referencia) | Mért |
|---|---|---|
| A — chord observation után érkező strum | `at = 1.066 − 0.150 = 0.916 s` | **`1.000 s`** (+84 ms) |
| B — strum nélküli frame chord change-pointtal | `at = timelineNow = 2.000 s` | **`1.700 s`** (−300 ms) |

Nyers kimenet:

```
PRÓBA A: strum.at = 0:00:01.000000 · legacy referencia = 0:00:00.916000 · eltérés = 0:00:00.084000
PRÓBA B: chord.at = 0:00:01.700000 · timelineNow = 0:00:02.000000 · lag-warningok = []
```

## 4. Leletek

### MAJOR-1 — a frame-kézbesítési lag a CHORD observationökre is rámegy, egy MÁSIK esemény lagjával

`lib/features/practice/data/live_practice_observation_gateway.dart:194`,
`:204-229`

A `_handleFrame` minden frame-re kiszámolja a lagot
(`engineTimeSec − latestStrumTime`), majd **ugyanazt az `at`-t** adja a
`StrumObservation`-nek és a `ChordObservation`-nek is (`:211`).

A `frameDeliveryLag` fogalmilag a **strum-becsapódás** klasszifikációs késése.
Egy chord change-point ehhez nem tartozik hozzá — pláne, hogy a Live
`latestStrum*` mezői a chunk 014 és a `learn_screen.dart` szerint **~2 s-ig
„ottragadnak"**, tehát strum nélküli frame-en a lag egy régen lezajlott,
**másik** eseményből származik.

**Mérve (PRÓBA B):** egy 300 ms-os beégett `latestStrumTime` mellett a
`G` akkord change-pointja `2.000 s` helyett **`1.700 s`**-ra került — 300 ms-mal
a múltba, egy hozzá nem tartozó lag miatt. A `maxFrameDeliveryLag` (500 ms) alatt
ez néma; fölötte 0-ra esik, de akkor egy fölösleges warningot ír (MINOR-1).

**Legacy referencia:** `learn_screen.dart:204-205` — `_scorer!.observeChord(chord,
_elapsedSec)`, azaz a chord a **korrigálatlan** eltelt időt kapja; a de-jitter
kizárólag a `registerStrum` ágon van. Az [ADR 0074 §3](../adr/0074-practice-observation-gateway.md)
kimondja, hogy a kör ezt a felosztást őrzi meg.

**Javasolt irány (nem kész patch):** a lag kiszámítása és alkalmazása kizárólag
ott, ahol ÚJ strum van a frame-en (`emitStrum == true`); a `ChordObservation`
`at`-ja a korrigálatlan `timelineNow()`.

**Részben a brief hibája:** a §5.5 „Minden emittált observationre" fordulata
erre csábított. A javítás dokumentált **brief-revízió R2**-vel járjon, ne néma
kódmódosítással.

### MAJOR-2 — a közös monoton clamp KIOLTJA a strum de-jittert

`lib/features/practice/data/live_practice_observation_gateway.dart:275-281`

A `_observationAt` egyetlen, **observation-fajtától független** padlót vezet
(`_lastEmittedAt`). Mivel a chord observation a de-jitterezetlen (vagy MAJOR-1
szerint idegen laggal tolt) pillanatra kerül, és a gateway **minden**
change-pointon plusz `chordStableDuration`-onként (180 ms) emittál chordot, a
padló folyamatosan a chord időbélyegére ugrik. A rá következő strum
`timelineNow − lag` értéke ez alá esik → **felfelé clampelődik**, azaz a
korrekció elvész.

**Mérve (PRÓBA A):** t=1.000 s-on egy chord observation (at = 1.000), majd
t=1.066 s-on egy új strum 150 ms-os laggal. Helyes érték `0.916 s`, mért érték
**`1.000 s`** — a de-jitter 84 ms-ból **0-t** hagyott meg.

Ez nem széleset érint: a mért Live kadencia ~66 ms, a klasszifikációs késés
85–165 ms (chunk 014 / r147), tehát `timelineNow − lag` **rendszerint** kisebb az
előző frame idejénél. A kör központi időzítési funkciója a normál esetben
hatástalan.

**Miért nem fogta meg a property-őr:** a §6.9 invariáns a **teljes stream**
monotonitását méri, amit a globális padló definíció szerint teljesít — az őr
tehát pont azt a mechanizmust igazolja, ami a hibát okozza. (Az implementer
valódi-sértés próbája ezért lett helyesen piros, és mégsem mutatta ki ezt.)

**Javasolt irány:** fajtánként külön padló (`_lastEmittedStrumAt` /
`_lastEmittedChordAt`), a §6.9 monotonitás-invariáns **fajtánként**
újrafogalmazva. A brief R2 mondja ki a nem elfogadható gyengítést is:
**a fajtafüggetlen, globális padló NEM elfogadható**, mert kioltja a de-jittert.

### MINOR-1 — fölösleges lag-warning strum nélküli frame-eken

`live_practice_observation_gateway.dart:194`, `:244-251`

A lag minden frame-re kiszámolódik, akkor is, ha nincs új strum. A beégett
`latestStrumTime` néhány száz ms után túllépi a `maxFrameDeliveryLag`-et, így a
gateway a session hátralévő részében **másodpercenként egy** „frame lag out of
range" warningot ír — olyan problémáról, ami nem létezik. A rate limit miatt nem
log-özön, de félrevezető diagnosztika.

Ugyanannak a gyökérnek a mellékhatása, mint a MAJOR-1 — azzal együtt megszűnik.

### NOTE-1 — a `_lastSeenStrumSeq` kezdőértéke `-1`, a legacy alap `0`

`live_practice_observation_gateway.dart:42`, `:179`

A legacy predikátum `frame.strumSeq > _lastSeq` **`_lastSeq = 0`**-ról indul,
tehát a `strumSeq == 0` (a `LiveFrame` default) sosem tüzel. Itt `-1`-ről indul,
így egy `strumSeq: 0` + nem-null `latestStrum` frame observationt adna. A
`LivePipeline` ma minden valódi strumra ≥1-et ad, tehát nem elérhető — de néma
eltérés a befagyasztott legacy predikátumtól. Javítható a javító körben egy sorral.

### NOTE-2 — a handoff §10.3/2 állítása pontatlan: a nem-véges confidence nem „megkonstruálhatatlan"

A handoff szerint a NaN/±Infinity confidence „a publikus API-n keresztül nem
érhető el", mert a `Strum` konstruktora assertál. A Dart **assertjei csak debug
módban futnak** — release buildben a NaN igenis konstruálható, tehát a kódban
lévő `isFinite` őr **nem holt kód**, hanem élő védelem.

Az őr maradjon; a *handoff állítása* javítandó. (A `NaN >= min` amúgy is `false`,
tehát a küszöb önmagában is szűrne — de az `isFinite` a szándék kimondása.)

### NOTE-3 — a §6.8 log-fegyelem teszt fixture-default vakfoltja

`test/…/live_practice_observation_gateway_test.dart:927-928` — a 200 frame a
`_frame(...)` defaultjával megy, ahol `engineTimeSec == latestStrumTime == -1`,
azaz **hiányzó engine-óra**. Pontosan az a pont, ahol a MINOR-1 warning-özön nem
tud megjelenni. Klasszikus L10-alakzat: a teszt zöld, mert a default olyan
cellát választ, ahol a hibás és a helyes viselkedés azonos.

## 5. Ami mérten JÓ

- **A §6.2 lag-mátrix hibátlan.** A 9 sor × 2 `timelineNow` mind a 18 cellája
  külön teszt, a várt `at` literálisan; a szigorú `<` határpont (`lag == 500 ms`)
  helyesen NEM vonódik le, és warningot ír. A brief-revízió R1-et pontosan követi.
- **Az aktivációs tábla szó szerint a brief §5.3-a**, mind a 11 státuszra, a
  kulcshalmaz-egyezés tesztjével és a külön `paused → false` teszttel; a
  `practiceCaptureActive` hiányzó kulcsra `StateError`-t dob, nem csendes
  `false`-ot.
- **A valódi-sértés próba valódi volt.** A clamp eltávolítása után az implementer
  által közölt piros kimenetet a diff és a property-teszt szerkezete alátámasztja
  (a másik négy property zöld maradt — nincs túlmérés).
- **Scope- és architektúra-fegyelem hibátlan:** 13 fájl, tilos zóna 0 sor,
  allowlist változatlan, a Live feature-t csak a `public.dart` barrelen éri el.
- **A `stopped` szerződés helyes használata:** a kör közben megállt, és a
  **brief-szerző (Claude) hibáját** fogta meg (§0.0 R1). Ez a kívánt viselkedés.
- **A handoff becsületes:** a gate-összegzés csonkítatlan, a valódi-sértés próba
  kimenete tényleges, az eltérések (§10.3) fel vannak sorolva. A `| tail` tiltást
  megtartotta.

## 6. Merge-döntés

**MERGE TILOS.** Két MAJOR nyitva; mindkettő a kör központi időzítési
szerződését érinti, és mindkettő zöld gate alatt élt.

A javító kört **ugyanaz a motor (MiniMax M3)** viszi, a fenti findings-listával,
és **brief-revízió R2-vel** kell kezdeni (a §5.5 „minden emittált observationre"
fordulata és a §6.9 monotonitás-invariáns pontosítása) — a MAJOR-1 gyökere
részben a brief.

A javító kör kötelező eleme, hogy a két MAJOR-hoz **olyan teszt szülessen, ami a
mai kódot pirosra fogta volna** (a fenti két próba mércéje), és hogy a §6.9
property-őr fajtánként mérje a monotonitást.

## 7. Javító kör (R1) — a Claude tölti ki a re-review után
