# E02-R03 — Review

Brief: `docs/rounds/e02-r03-domain-models.md`
Diff: `git diff f6aefad..4bab1ec` (29 fájl, +4232 / −6 a brief-committól; a
brief-fájlban kizárólag a §10 kitöltése, +167/−2)
Reviewer: Claude · Dátum: 2026-07-30
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 3

A kör a Practice V2 teljes domain-szerződését szállítja pontosan a brief §3.1/a–i
és az ADR 0068 keretei között: 13 új pure-Dart modellfájl + a `meter.dart`
MINOR-1 zárása, 12 új tesztfájl 101 új unit-teszttel (összesen 125 a domain
könyvtárban). Minden aggregátum immutable `final class`, aggregáló, lista-alapú
`validate()`-tel és stabil, perzisztálható kódokkal; a listát/mapet hordozó
típusok strukturális egyenlőséget kapnak a §3.1/i helper révén. Hívó kód
továbbra sincs — a production viselkedést kizárólag a kért `Meter.ticksPerBar`
szimmetrikus fail-fast érinti. Scope-sértés nincs: a diff fájllistája tételesen
azonos a §4 táblával, a tilos zóna (kiemelten `beat_position.dart`,
`tempo.dart`, `lib/core/**`, `tool/**`, `docs/adr/**`) érintetlen.

Megjegyzendő körülmény: az implementáló Codex-process 13:35-kor gépoldali okból
megszakadt (az utolsó purity-teszt futtatás közben); ugyanaz a session
resume-mal folytatta, a teljes gate-mátrixot frissen újrafuttatta (§10.4), majd
zárta a kört. A megszakadás előtti és utáni állapot diffje csak a lezáró
finomításokat tartalmazza — elveszett munka nincs.

## Kötött döntések (brief §5) — szúrópróba-audit

| Döntés | Bizonyíték | Állapot |
|---|---|---|
| §5 validation-as-value: aggregáló `validate()`, nem throw | minden modellben `List<PracticeValidationFailure>` + `List.unmodifiable`; kivétel egyedül a kért `ticksPerBar` fail-fast getter | ✅ |
| §5/9 kötött kódkészlet, bővítés nélkül | 60 kód a katalógusban (reviewer-oldali `rg`-számlálás: 60), mind literálisan tesztelt; §10.5 szerint bővítés nem történt | ✅ |
| Integer-percent súlyok/küszöbök | `ScoringProfile.weights: Map<PracticeScoreDimension, int>`, nem-üres map összege pontosan 100, küszöbök 0–100 zárt | ✅ |
| Kanonikus chord-label (24 sharp-spelled major/minor vagy null) | `_canonicalPracticeChordLabels` set + `isCanonicalPracticeChordLabel` predikátum, event-validációba kötve | ✅ |
| Ablak-rendezés: `perfect <= good <= match`, szigorúan pozitív | `scoring_profile.dart:105-122` + zárt végpontos boundary-teszt | ✅ |
| Stabil enum-kódok + fallback nélküli `fromCode` | minden enum `code` mezővel; `*FromCode` `null`-t ad vissza ismeretlen kódra; roundtrip + egyediség teszt (`practice_enums_test.dart`) | ✅ |
| Marker ⊕ scored kizárás | `eventMarkerScorable` / `eventScorableMissing` kettős ág, mindkettő tesztelt | ✅ |
| Definition-aggregáció: rendezettség, id/pozíció-egyediség, tartomány, mode↔profile kompatibilitás | `practice_definition.dart:102-159` — nested `validate()`-ök TOVÁBBRA IS lefutnak aggregátum-hiba mellett (a session-aggregációs korai-`break` regressziót a Codex saját audita valódi RED-del fogta, §10.2) | ✅ |
| MINOR-1 (E02-R02): `ticksPerBar` szimmetrikus fail-fast | `meter.dart` diff: `beatsPerBar` tartomány-őr ugyanúgy `StateError`, mint az eddigi `beatUnit`-ág; mindkét ág tesztelt (`meter_test.dart` +13) | ✅ |
| Purity-őr test-oldalon | `domain_purity_test.dart` (244 sor): forrás-szkennelő, komment/string false-positive szűréssel; valódi-sértés próba §10.3 (RED exit 1 → GREEN exit 0) | ✅ |

## Gate-bizonyíték (reviewer-oldali független futtatás)

Izolált friss klón: `/tmp/ss-review-e02r03` (GitHub-ról, `4bab1ec`), nem a
Codex munkapéldánya.

| Parancs | Eredmény |
|---|---|
| `dart format --set-exit-if-changed lib test` | 482 fájl, **0 changed**, exit 0 |
| `flutter analyze lib/ test/` | **No issues found!** |
| `flutter test test/features/practice/domain/` | **+125: All tests passed!** |

A scope-audit szintén független: `git diff --name-only f6aefad..4bab1ec`
↔ brief §4 tábla — tételes egyezés, 29/29.

## NOTE-ok (nem blokkolók)

1. **NOTE — caller-immutability szerződés:** a `const` konstruktorok listái/
   mapjei (pl. `ScoringProfile.weights`, `PracticeDefinition.events`) nem
   másolódnak defenzíven — ez az ADR 0068 tudatos döntése, a doc-commentek
   rögzítik. Ha az R18 (perzisztencia) körben nem-const forrásból épülnek,
   ott unmodifiable-becsomagolás kell a betöltőben.
2. **NOTE — `listEquals`/`mapEquals` név-ütközés:** a `practice_value_equality.dart`
   helperei névre egyeznek a `flutter/foundation` azonos nevű függvényeivel.
   Domain-fájlban a purity-őr miatt foundation-import úgysem jelenhet meg, de
   vegyes importú (nem-domain) hívóhelyen a jövőben import-prefix kellhet.
3. **NOTE — chord-label készlet duplikáció-kockázat:** a 24 kanonikus label a
   domainben lokális konstans; a Kör 5 adapterei a `core/music` oldali
   akkordkészletből képeznek majd erre — az adapter-körben egy egyirányú
   konzisztencia-teszt (minden adapter-kimenet kanonikus) indokolt.

## Verdikt

**APPROVED** — merge-re bocsátható az ADR 0052 zöld gate (CI: gate-sor + teljes
suite + randomizált property + APK + coverage) teljesülése után.
