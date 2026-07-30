# E02-R02 — BeatPosition, Tempo és Meter értékobjektumok

Státusz: PLANNING (kód olvasva: `main` @ `d988566`, 2026-07-30)
SDD: `docs/sdd/03-epic-02-practice-engine.md` § „Kör 2 — BeatPosition, Tempo és Meter értékobjektumok" + §9.1–9.3
Branch: `codex/epic-02-round-02-musical-time`
Brief szerzője: Claude · Implementáció: Codex
**Előfeltétel: E02-R01 merge-ölve (PR #22, `main` @ `57f37ea`).** Teljesült.

## 1. Cél

A Practice V2 domain első kódja: a zenei idő **egzakt, integer-tick alapú**
értékobjektumai ([ADR 0066](../adr/0066-practice-tick-time-model.md), 480 PPQ),
a tempó- és metrumvalidáció, valamint az egyetlen, auditált legacy
`double beat` → tick konverziós híd. A kör kimenete pure Dart könyvtárkód
teszt-lefedettséggel — **nincs UI, nincs provider, nincs futásidejű belépési
pont**, tehát a felhasználói viselkedés változatlan marad (a
`practiceEngineV2Enabled` flag wiring későbbi kör dolga). Minden későbbi
Epic-2 kör (modellek R03, katalógus R04, adapterek R05, target compiler R06,
scorer R09/R10) erre a négy fájlra épül; ezért itt dől el, hogy a triola
kifejezhető-e epsilon nélkül.

## 2. Jelenlegi állapot

Mért tények, `main` @ `d988566` (2026-07-30) olvasása alapján.

### 2.1 Nincs practice feature

- **`lib/features/practice/` és `test/features/practice/` nem létezik**
  (könyvtárlistázással ellenőrizve). A mai `practice_*` fájlnevek a Progress
  (`practice_entry.dart`, `practice_log_repository.dart`) és a Learn
  (`practice_speed_provider.dart`) feature-höz tartoznak — ezekhez a kör nem ér.
- Névütközés nincs: a repóban nem létezik `Tempo`, `Meter`, `BeatPosition`
  vagy `PracticeValidation*` nevű típus (grep); a leghasonlóbb a
  `TempoTracker` (`lib/features/live/engine/dsp/tempo_tracker.dart:5`), ami
  DSP-osztály, nem érintett.

### 2.2 A kiváltandó `double`-minta (referencia, NEM módosítható)

- `lib/features/learn/model/lesson.dart:20` — `final double beat;` a legacy
  event-pozíció, nyolcad-felbontáson (a pattern-expander `x.0`/`x.5` értékeket
  ad, ezek binárisan egzaktak — ezért nem tört még el semmi).
- `lib/features/learn/model/lesson.dart:109` — `e.beat % 1.0 == 0`: pontosan
  az a `double`-egyenlőség, amelyet az ADR 0066 kivált; triolánál (1/3) ez a
  minta hibás lenne.
- A teljes mért baseline (konstansok, viselkedés, ismert rések):
  [`docs/baseline/epic-02-practice-start.md`](../baseline/epic-02-practice-start.md)
  (E02-R01, a Learn azóta nem változott).

### 2.3 Kész elemek, amikre a kör épít

- **ADR 0066 elfogadva** (E02-R01-ben megírva, ez a kör implementálja):
  480 PPQ, negyed=480 / nyolcad=240 / tizenhatod=120 / nyolcad-triola=160 /
  negyed-triola=320 tick; negatív pozíció tilos; count-in session-fogalom;
  egyetlen legacy konverziós helper mért toleranciával.
- `FeatureFlags.practiceEngineV2Enabled` létezik (E02-R01): nonProd ON /
  production OFF. **E körben nincs mit flag mögé tenni** — a domain-fájloknak
  nincs hívójuk; a wiring az R05+ köröké.
- `lib/core/foundation/app_failure.dart:55` — az `AppFailure` **sealed**,
  tehát a practice domain nem is tudná kívülről bővíteni; a domain saját,
  önálló validációs hibatípust kap (§5/6).

### 2.4 Az architektúra-őr mai állapota

`tool/check_architecture.dart` (659 sor):

- `_isSharedDomain` (`:229-231`) ma két útvonalat véd framework-függőség
  ellen: `lib/core/music/` és `lib/core/audio/codec/`.
- A tiltott függőség-készlet (`_isForbiddenDomainDependency`, `:233-246`):
  `package:flutter/`, `flutter_localizations`, `flutter_riverpod`, `riverpod`,
  `dio`, `shared_preferences`, `flutter_gen/gen_l10n`, `lib/l10n*`.
- A szabályleírás (`:576-583`): „shared music/audio domain must remain
  framework-independent".
- Cross-feature import csak `public.dart`-on át (`:213-226`) — e körben nem
  releváns: a practice feature-t senki nem importálja, és a checker csak a
  `lib/` fát nézi, a teszteket nem.
- Tesztje: `test/core/architecture_dependency_test.dart:181` — „keeps shared
  music and WAV codec domains framework-free" (szintetikus fájlfával próbálja
  a szabályt).

Az SDD Kör 2 elfogadási feltétele („domain Flutter-független") ma tehát
**nincs gépi őr alatt** a `lib/features/practice/domain/` útvonalra — a kör
ezt az őrt is felhúzza (§3.1/c), különben az invariáns csak konvenció lenne.

### 2.5 ADR-számozás

A legmagasabb foglalt szám **0067**. Ez a kör **nem oszt ki új ADR-t** — minden
architekturális döntése az ADR 0066-ban már rögzített (ott „decided here,
implemented in E02-R02"). A 0068 szabad marad a következő döntést hozó körnek.

## 3. Scope

**Benne (Codex):**

- **§3.1/a Értékobjektumok.** `BeatPosition` (480 PPQ integer tick,
  `Comparable`, összeadás/kivonás, biztonságos subdivision-factoryk),
  `Tempo` (BPM + validáció), `Meter` (beatsPerBar/beatUnit + validáció,
  `ticksPerBar`), mind pure Dart, a §5 kötött döntései szerint.
- **§3.1/b Validációs alap.** `practice_validation.dart` — a domain önálló,
  aggregáló (lista-alapú) validációs hibatípusa stabil kódokkal.
- **§3.1/c Gépi őr.** A `tool/check_architecture.dart`
  framework-independence szabályának kiterjesztése a
  `lib/features/practice/domain/` útvonalra + tesztbővítés, valódi-sértés
  próbával.
- **§3.1/d Legacy híd.** Az egyetlen `double beat` → `BeatPosition` konverziós
  helper és inverze, dokumentált toleranciával (ADR 0066 §5).

**Kívül (ebben a körben TILOS):**

- **Bármilyen production viselkedésváltozás.** `lib/features/learn/**`,
  `lib/features/progress/**`, `lib/features/streak/**` és minden más meglévő
  feature egyetlen sora sem módosulhat. A `lesson.dart` `double beat`-je
  marad — a Lesson→PracticeDefinition adapter az R05 köre.
- R03+ modellek: `PracticeEvent`, `PracticeDefinition`, `PracticeMode`,
  `PracticeSource`, observation/verdict típusok — SEMMI ilyen ebben a körben,
  akkor sem, ha „kézenfekvő lenne előre hozni".
- JSON-szerializáció (`toJson`/`fromJson`) — a perzisztencia-séma az
  R03/R04/R06 köröké; a doc-comment rögzíti, hogy a kanonikus tárolt forma a
  nyers integer `ticks` (ADR 0066 §4), de kód még nem kell hozzá.
- `lib/features/practice/public.dart` — amíg nincs cross-feature fogyasztó,
  nincs publikus API-döntés; az a kör hozza létre, amelyik az első importálót.
- `lib/app/**` (flagek, config) — a flag-tábla az R01-ben lezárt, wiring R05+.
- `lib/core/**` — a practice domain NEM a core-ba kerül (feature-first);
  a `core/music` bővítése sem e kör dolga.
- E02-R01 parity-eszközök: `test/support/practice_baseline_scenarios.dart`,
  `test/fixtures/practice/**`, `test/features/learn/**` — érintetlenek.
- Meglévő teszt átírása/gyengítése/törlése. Piros meglévő teszt = **MEGÁLLÁS
  és jelentés.** A `test/core/architecture_dependency_test.dart` bővülhet, de
  meglévő assertion nem gyengülhet.
- DSP/ML paraméter, modell-bináris, `docs/rag/chunks/` (AGENTS.md §9).
- Új package, code generation, új `--dart-define` (SDD Ch3 §26/8–9, ADR 0065 §3).
- `docs/adr/**` (nincs új ADR, §2.5), `HANDOFF.md`, `README.md`, `.github/**`,
  `backend/**`, `ml/**` — Claude-oldal ill. scope-on kívül.
- Randomizált property-teszt (`test/property/`): NEM kell — ez nem DSP-
  viselkedés (HANDOFF §7 szabálya DSP-re szól), a domain egzakt integer-
  aritmetika, determinisztikus unit-tesztekkel teljesen fedhető.

## 4. Engedélyezett fájlok

Csak az alábbi útvonalak módosíthatók. Bármi más → **MEGÁLLÁS és jelentés**.

| Útvonal | Miért |
|---|---|
| `lib/features/practice/domain/model/beat_position.dart` | ÚJ — §3.1/a+d: tick-értékobjektum + legacy híd |
| `lib/features/practice/domain/model/tempo.dart` | ÚJ — §3.1/a: BPM + validáció |
| `lib/features/practice/domain/model/meter.dart` | ÚJ — §3.1/a: metrum + validáció |
| `lib/features/practice/domain/model/practice_validation.dart` | ÚJ — §3.1/b: a validációs hibatípus |
| `test/features/practice/domain/beat_position_test.dart` | ÚJ — a §6 kötelező tick/roundtrip/sort/triola tesztjei |
| `test/features/practice/domain/tempo_test.dart` | ÚJ — BPM-határok, NaN/∞, hibakódok |
| `test/features/practice/domain/meter_test.dart` | ÚJ — 4/4 és 3/4, érvénytelen értékek, `ticksPerBar` |
| `test/features/practice/domain/practice_validation_test.dart` | ÚJ — a hibatípus value-semantics + aggregáció |
| `tool/check_architecture.dart` | §3.1/c — a framework-independence útvonal-készlet + szabályleírás bővítése (KIZÁRÓLAG ez; az allowlist és a többi szabály érintetlen) |
| `test/core/architecture_dependency_test.dart` | §3.1/c — új teszteset a practice-domain őrre (meglévő assertion nem gyengülhet) |
| `docs/rounds/e02-r02-musical-time.md` | **kizárólag a 10. szekció** |

**Tilos zóna:** minden más — kiemelten `lib/features/**` (a fenti négy ÚJ
fájlon kívül MIND), `lib/app/**`, `lib/core/**`, `test/support/**`,
`test/fixtures/**`, `test/features/learn/**`, `docs/adr/**`, `docs/baseline/**`,
`HANDOFF.md`, `.github/**`, `backend/**`, `ml/**`, `pubspec.yaml`.

## 5. Kötött architekturális döntések

Ezeket a kör NEM tervezheti újra. Új ADR nincs (§2.5) — a kötelező érvényű
döntés az [ADR 0066](../adr/0066-practice-tick-time-model.md); az alábbiak
annak e körre vetített, kötött következményei:

1. **`BeatPosition` = integer tick, 480 PPQ** (`static const int ticksPerBeat
   = 480`), `final class`, `Comparable<BeatPosition>`. Egyenlőség/rendezés/
   aritmetika kizárólag integer-műveletek. **Semmilyen API nem vesz át és nem
   ad vissza `double` zenei pozíciót** — az egyetlen kivétel a legacy híd (5. pont).
2. **A subdivision-factoryk integer szorzások**, nem `double`-kerekítések:
   negyed (480), nyolcad (240), tizenhatod (120), nyolcad-triola (160) —
   `int` darabszám-paraméterrel. Így `3 × nyolcad-triola == 1 × negyed` egzakt
   `==`-vel igaz, tolerancia-argumentum sehol nincs.
3. **Negatív pozíció nem konstruálható.** Az SDD §9.1 vázlata szerinti
   `const` konstruktor `assert(ticks >= 0)`-t kap — de mivel az assert release
   módban kioptimalizálódik, **minden adatvezérelt út** (factoryk, legacy híd,
   kivonás) minden build-módban ható, valódi kivétellel (`ArgumentError`)
   utasítja el a negatívot. A kivonásnál nincs csendes nullára-vágás. A
   count-in NEM negatív pozíció, hanem session-fogalom (ADR 0066 §3) — e
   körben nem is szerepel.
4. **`Tempo`:** `double bpm` (a BPM valóban folytonos mennyiség — az ADR 0066
   §2 `double`-tilalma a *zenei pozícióra* vonatkozik, az időtartam-jellegű
   mennyiségekre nem), érvényes tartomány **30.0 ≤ bpm ≤ 300.0, zárt
   intervallum** (SDD §9.2); NaN és ±∞ érvénytelen. Clamp-elés NINCS a
   domainben — az import-adapter (R05) dönt clamp vs. failure között, ehhez
   kell neki a lista-alapú validáció.
5. **A legacy híd egyetlen, auditált pontja** a `BeatPosition`-ön él:
   `double beat` → tick konverzió `(beats * 480).round()`-dal + az inverz
   (`tick / 480.0`). A doc-comment számszerűen rögzíti a toleranciát: a
   kerekítési hiba legfeljebb **1/960 beat** (fél tick), és a mai nyolcad-grid
   (`x.0`/`x.5`) valamint minden 480-osztó subdivision **nulla eltéréssel**,
   roundtrip-egzaktan konvertál. Negatív input itt is `ArgumentError`.
6. **`Meter`:** `int beatsPerBar` + `int beatUnit` (default 4). Érvényes
   tartomány: `1 ≤ beatsPerBar ≤ 16`, `beatUnit ∈ {2, 4, 8}` (a UI szűkíthet;
   4/4 és 3/4 kötelezően valid — SDD §9.3). `ticksPerBar` getter
   integer-egzakt: beatUnit 4 → `beatsPerBar × 480`, beatUnit 8 → `× 240`,
   beatUnit 2 → `× 960`. **A `8 slot/bar` feltevés sehol nem éghet be** —
   slot-fogalom ebben a domainben nem létezik.
7. **Validáció = érték, nem kivétel** (a data-vezérelt útra): a
   `practice_validation.dart` önálló `PracticeValidationFailure` value-típust
   ad (stabil `code` string + emberi `message`, `==`/`hashCode`/`toString`),
   és a `Tempo`/`Meter` validációja **aggregáló listát** ad vissza (üres =
   valid) az `AppConfig.resolve` `problems`-mintájára — nem az első hibánál
   áll meg. Kötött kódkészlet: `tempo.bpm.notFinite`, `tempo.bpm.outOfRange`,
   `meter.beatsPerBar.outOfRange`, `meter.beatUnit.unsupported`,
   `beatPosition.negative`. A domain NEM függ a `core/foundation`
   `AppResult`/`AppFailure` típusaitól (az `AppFailure` sealed, §2.3; a
   domain önállósága a cél).
8. **Pure Dart, gépi őrrel.** A négy lib-fájl csak `dart:` core-t és egymást
   importálhatja (e körben a `core/music`-ra sincs szükség). Az őr: a
   `tool/check_architecture.dart` framework-independence útvonal-készlete
   (`:229-231`) kiegészül a `lib/features/practice/domain/` prefixszel, a
   szabályleírás (`:578-579`) szövege ennek megfelelően frissül, és a
   `test/core/architecture_dependency_test.dart` a `:181` minta szerint új,
   szintetikus esetekkel bizonyítja (practice-domain + flutter-import →
   violation; practice-domain + dart-core → tiszta). A checker többi szabálya
   és a deviáció-allowlist változatlan.
9. **Fájlszervezés az SDD Kör 2 listája szerint** (§ „Új fájlok") — a négy
   modellfájl a `lib/features/practice/domain/model/` alatt, barrel/`public.dart`
   nélkül.

## 6. Acceptance criteria

- [ ] **Exact fractions:** teszt állítja, hogy negyed=480, nyolcad=240,
      tizenhatod=120, nyolcad-triola=160 tick, és hogy 3 nyolcad-triola
      `==` 1 negyed, 2 tizenhatod `==` 1 nyolcad — egzakt egyenlőséggel,
      tolerancia nélkül.
- [ ] **Triola-precizitás:** 6 nyolcad-triola == 2 negyed == 960 tick; a
      legacy hídon át a `1/3` beat (`0.3333…`) a legközelebbi tickre (160)
      kerekül, és ez dokumentált, tesztelt viselkedés.
- [ ] **Roundtrip:** minden támogatott subdivision-pozícióra (a tesztben fix,
      determinisztikus tick-lista) `legacy(tick→beat→tick)` identitás; a mai
      nyolcad-grid értékekre (`0.0, 0.5, 1.0, …`) nulla eltérés.
- [ ] **Legacy konverzió:** `0.5 → 240`, `1.0 → 480`, `1.5 → 720` tesztelve
      (SDD Kör 2 kötelező lista), a tolerancia (≤ 1/960 beat) a konverziós
      helper doc-commentjében számszerűen szerepel.
- [ ] **Negatív elutasítás:** negatív tick, negatív legacy beat és negatívba
      futó kivonás egyaránt `ArgumentError`-t dob (nem assert-only út,
      §5/3); teszt mindhárom útra.
- [ ] **Rendezés:** fix, kevert (nem random) pozíció-lista `sort()` után a
      várt sorrend; `compareTo` konzisztens az `==`-vel (azonos tick ⇒ 0 és
      egyenlő); összeadás/kivonás tesztelt.
- [ ] **Tempo-validáció:** 30.0 és 300.0 határértéke VALID (zárt intervallum),
      29.9…/300.00…1 invalid `tempo.bpm.outOfRange` kóddal, NaN/±∞ invalid
      `tempo.bpm.notFinite` kóddal; az aggregáló lista üres a valid esetben.
- [ ] **Meter-validáció:** 4/4 és 3/4 valid; `beatsPerBar` 0 és 17 invalid;
      `beatUnit` 5 invalid `meter.beatUnit.unsupported` kóddal; `ticksPerBar`:
      4/4 → 1920, 3/4 → 1440, 6/8 → 1440.
- [ ] **Flutter-függetlenség GÉPPEL bizonyítva:** a
      `dart run tool/check_architecture.dart` zölden fut, és a **valódi-sértés
      próba** dokumentálva a §10-ben: egy ideiglenes
      `import 'package:flutter/foundation.dart';` a `beat_position.dart`-ban →
      a checker ÉS a `test/core` teszt piros → visszavonva → zöld.
- [ ] A négy lib-fájl importlistája kizárólag `dart:` core és egymás
      (a diffben ellenőrizhető); Flutter/Riverpod/Dio/l10n import nincs.
- [ ] **`git diff --stat` a §4 listán kívül semmit nem érint**; meglévő fájl
      csak a `tool/check_architecture.dart` és a
      `test/core/architecture_dependency_test.dart` (ott is csak bővítés).
- [ ] A meglévő tesztek zöldek: `test/core`, `test/app`,
      `test/features/learn` (§7) — egyiket sem módosította a kör (az
      architektúra-teszt bővítésén kívül).

## 7. Kötelező ellenőrzések

Külön parancsokként (`AGENTS.md` §12 — **soha ne láncold `&&`-del**, és
`analyze` + `test` soha nem egy hívásban):

```bash
~/flutter/bin/flutter pub get
```
```bash
~/flutter/bin/dart format --output=none --set-exit-if-changed lib test tool
```
```bash
~/flutter/bin/flutter analyze lib/ test/ tool/
```
```bash
~/flutter/bin/flutter test test/features/practice
```
```bash
~/flutter/bin/flutter test test/core
```
```bash
~/flutter/bin/flutter test test/app
```
```bash
~/flutter/bin/flutter test test/features/learn
```
```bash
~/flutter/bin/dart run tool/check_architecture.dart
```

A teljes suite + randomizált property gate + APK a CI-ban
([ADR 0052](../adr/0052-ci-apk-automerge-session-per-round.md) /
[ADR 0053](../adr/0053-ci-full-test-suite.md)). **A `gh` hívás, a CI-dispatch,
a PR és a merge Claude-oldal** ([ADR 0064](../adr/0064-codex-hands-over-ci-at-code-complete.md))
— a Codex ne futtasson `gh`-t.

## 8. Implementációs sorrend

1. `practice_validation.dart` + tesztje (value semantics, kódkészlet). RED →
   GREEN.
2. `beat_position.dart` TDD-vel: előbb a §6 tick/roundtrip/negatív/sort/triola
   tesztek (RED — a típus még nincs), majd az implementáció (GREEN).
3. `tempo.dart` és `meter.dart` ugyanígy (határérték-tesztek előbb).
4. Architektúra-őr: a `test/core/architecture_dependency_test.dart` új esete
   előbb (RED — a checker még nem ismeri az útvonalat), majd a
   `tool/check_architecture.dart` bővítése (GREEN).
5. Valódi-sértés próba a §6 szerint (ideiglenes flutter-import → piros →
   visszavonás → zöld), kimenete a §10-be.
6. `format` → `analyze` → §7 tesztek → `check_architecture` — külön
   hívásokként; a §10 kitöltése a TÉNYLEGES kimenetekkel.
7. Kör-jelzés: `tools/codex-signal.sh done|stopped|blocked` (AGENTS.md §15.2).

## 9. Kockázatok

- **A checker-módosítás merge-gate-közeli.** A `check_architecture.dart` a CI
  gate-sor része; ha a bővítés hibás (pl. a prefix-illesztés a `lib/features/
  practice/` NEM-domain részeire is rászól, vagy kivételt dob), az egész gate
  törik. Ezért kötelező a kétirányú bizonyítás: szintetikus teszt + valódi-
  sértés próba mindkét irányban (piros sértéskor, zöld visszavonás után).
- **Assert-only védelem csapdája.** A `const` konstruktor assertje release
  módban nem fut — ha a negatív-tiltás csak ott él, a release build csendben
  átenged érvénytelen állapotot. A §5/3 ezért követel valódi kivételt minden
  adatvezérelt útra; a review ezt kiemelten nézi.
- **Scope-csúszás a „kézenfekvő" irányba.** A PracticeEvent/Definition (R03),
  a JSON (R04/R06), a Lesson-adapter (R05) és a `public.dart` mind logikus
  folytatás — de mind TILOS e körben. A kör kicsi; maradjon az.
- **`double`-szivárgás.** Egy jószándékú `toBeats()`/`asDouble` kényelmi getter
  a pozíción visszahozná az epsilon-világot. Az egyetlen legális `double`-híd
  a legacy helper (§5/5) — a review a publikus API-t erre végigellenőrzi.
- **A triola-kerekítés elkenése.** A `1/3` beat NEM egzakt double; a híd
  kerekít, és ezt dokumentálni kell, nem elrejteni. Ha a teszt „szépítené"
  (pl. toleranciás összehasonlítással a tick-oldalon), az pontosan a tiltott
  minta — tick-oldalon csak egzakt `==` megengedett.
- **Formázás/lint az új fájlfán:** a `dart format` a `lib test tool` teljes
  fáján fut — az új könyvtárak is beleértendők, különben a CI format-gate
  bukik.

## 10. Implementation handoff — a Codex tölti ki

### Fájlonkénti összefoglaló

- `lib/features/practice/domain/model/practice_validation.dart` — önálló,
  pure-Dart `PracticeValidationFailure` value-típus és az öt kötött, stabil
  `PracticeValidationCode`.
- `lib/features/practice/domain/model/beat_position.dart` — 480 PPQ integer
  tick modell, checked runtime factory, egzakt subdivision-factoryk,
  `Comparable`, összeadás/kivonás és az egyetlen auditált legacy
  `double beat` híd. A helper doc-commentje rögzíti a legfeljebb `1/960 beat`
  (fél tick) kerekítési hibát.
- `lib/features/practice/domain/model/tempo.dart` — 30.0–300.0 BPM zárt
  tartományú, nem clampelő, lista-alapú validáció; NaN és ±∞ külön
  `notFinite` failure.
- `lib/features/practice/domain/model/meter.dart` — aggregáló
  beats-per-bar/beat-unit validáció és egzakt `ticksPerBar` 2/4/8
  nevezőkhöz.
- `test/features/practice/domain/{practice_validation,beat_position,tempo,meter}_test.dart`
  — 24 determinisztikus unit teszt a kódokra, value semanticsre, exact
  fraction/triola/roundtrip/legacy/negatív/rendezési utakra, BPM-határokra,
  aggregációra és meter tickekre.
- `tool/check_architecture.dart` — a framework-independent domain-prefixek
  kiegészítve kizárólag a `lib/features/practice/domain/` úttal; az allowlist
  és a tiltott dependency-készlet változatlan.
- `test/core/architecture_dependency_test.dart` — új szintetikus eset:
  practice-domain Flutter import tiltott, `dart:` import tiszta. Meglévő
  assertion nem változott.

### TDD RED → GREEN evidencia

- `practice_validation_test.dart`: RED exit 1 — a production fájl hiányzott,
  a `PracticeValidationCode`/`PracticeValidationFailure` feloldhatatlan volt;
  GREEN: `+3: All tests passed!`.
- `beat_position_test.dart`: RED exit 1 — a `beat_position.dart` és a teljes
  `BeatPosition` contract hiányzott; GREEN: `+11: All tests passed!`.
- `tempo_test.dart`: RED exit 1 — a `tempo.dart`/`Tempo` hiányzott; GREEN:
  `+4: All tests passed!`.
- `meter_test.dart`: RED exit 1 — a `meter.dart`/`Meter` hiányzott; GREEN:
  `+6: All tests passed!`.
- `architecture_dependency_test.dart`: RED exit 1 — az új practice-domain
  eset várt egy Flutter-sértést, az actual lista üres volt (`0 < 1`);
  GREEN a checker-prefix bővítése után: `+12: All tests passed!`.

### Valódi-sértés próba

Ideiglenesen ez az import került a valós
`lib/features/practice/domain/model/beat_position.dart` fájlba:

```dart
import 'package:flutter/foundation.dart';
```

Piros checker, exit 1:

```text
Architecture dependency check failed.
Unexpected violation(s) — fix them; adding an allowlist entry requires justification and an ADR:
- lib/features/practice/domain/model/beat_position.dart -> package:flutter/foundation.dart [shared music/audio and practice domains must remain framework-independent]
```

Piros `flutter test test/core`, exit 1:

```text
repository architecture contains exactly the allowlisted dependency deviations [E]
Expected: true
  Actual: <false>
- lib/features/practice/domain/model/beat_position.dart -> package:flutter/foundation.dart [shared music/audio and practice domains must remain framework-independent]
...
+286 -1: Some tests failed.
```

Az ideiglenes import eltávolítása után:

```text
Architecture dependencies OK (12 allowlisted deviation(s)).
+287: All tests passed!
```

### Kötelező gate-ek — tényleges kimenet

- `~/flutter/bin/flutter pub get` — exit 0; `Got dependencies!` (32 constraint
  miatt nem frissíthető package-ről tájékoztató üzenet, dependency-változás
  nélkül).
- `~/flutter/bin/dart format --output=none --set-exit-if-changed lib test tool`
  — exit 0; `Formatted 460 files (0 changed)`.
- `~/flutter/bin/flutter analyze lib/ test/ tool/` — exit 0;
  `No issues found! (ran in 9.9s)`.
- `~/flutter/bin/flutter test test/features/practice` — exit 0;
  `+24: All tests passed!`.
- `~/flutter/bin/flutter test test/core` — exit 0;
  `+287: All tests passed!`.
- `~/flutter/bin/flutter test test/app` — exit 0;
  `+47: All tests passed!`.
- `~/flutter/bin/flutter test test/features/learn` — exit 0;
  `+131 ~1: All tests passed!`; az egy skip a meglévő, env-varral indítható
  golden-generator.
- `~/flutter/bin/dart run tool/check_architecture.dart` — exit 0;
  `Architecture dependencies OK (12 allowlisted deviation(s)).`.

### Eltérések, nem futtatott ellenőrzések, follow-up

- A brief §5 kötött döntéseitől és §8 sorrendjétől nem volt eltérés.
- Teljes `flutter test`, randomizált property gate, CI és APK nem futott:
  ezek ADR 0052/0053/0064 és a brief §7 szerint Claude/CI-oldali feladatok.
  `gh` hívás nem történt. Backend/ML gate nem futott, mert ilyen fájl nem
  változott.
- Scope/import/secret audit: kizárólag a §4 engedélyezett kód- és
  tesztútvonalai érintettek; a négy lib-fájl csak egymást importálja, nincs
  framework/package import, R03+ modell, JSON, barrel, TODO/FIXME, production
  `print` vagy secret.
- Follow-up lelet: a globális együttműködési szabály által hivatkozott
  `docs/LESSONS.md` nem létezik ebben a repositoryban. Nem jött létre ebben a
  körben, mert nincs a §4 engedélyezett fájllistáján; Claude dönthet külön
  governance follow-upról.

## 11. Review — a Claude tölti ki

Link: `docs/reviews/e02-r02-review.md`
