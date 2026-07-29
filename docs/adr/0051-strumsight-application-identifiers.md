# ADR 0051 — StrumSight platform-azonosítók (a rename új appként települ)

**Státusz:** elfogadva (E01-R02, 2026-07-29).
Az SDD Ch2, Kör 2 §„Fontos migrációs kockázat" előírja, hogy ez a döntés ADR-ben
legyen dokumentálva.

## Döntés

A projekt minden azonosítója a StrumSight márkanévre áll át:

| Réteg | Régi | Új |
|-------|------|----|
| Dart package (`pubspec.yaml` `name:`) | `music_theory` | `strumsight` |
| Dart import prefix | `package:music_theory/` | `package:strumsight/` |
| Android `namespace` | `com.musictheory.music_theory` | `com.wolfcasaba.strumsight` |
| Android `applicationId` | `com.musictheory.music_theory` | `com.wolfcasaba.strumsight` |
| Android Kotlin package + mappa | `com/musictheory/music_theory` | `com/wolfcasaba/strumsight` |
| iOS `PRODUCT_BUNDLE_IDENTIFIER` | `com.musictheory.musicTheory` | `com.wolfcasaba.strumsight` |
| iOS teszt bundle | `com.musictheory.musicTheory.RunnerTests` | `com.wolfcasaba.strumsight.RunnerTests` |
| iOS `CFBundleName` | `music_theory` | `StrumSight` |
| Web `manifest.json` / `<title>` | `music_theory` | `StrumSight` |

A verziószám **nem változik** ebben a körben (`pubspec.yaml` marad `1.0.0+1`),
mert release-döntés nem született. A `pubspec.yaml` a kliensverzió egyetlen
forrása; az app futásidőben `package_info_plus`-szal olvassa, a README pedig
odamutat ahelyett, hogy saját verziószámot ismételne.

## Kontextus

A repót a recipewiser-mobile infrastruktúrájából örököltük, és a Flutter-projekt
`music_theory` néven jött létre — a termék viszont a legelső körtől StrumSight.
Az `android:label` és a `CFBundleDisplayName` már StrumSight volt, tehát a
felhasználó a *nevet* eddig is helyesen látta; a gépi azonosítók maradtak
elmaradva. Ez SDD Ch2 §3.4 adósságként volt nyilvántartva.

## Következmény: az app ÚJ alkalmazásként települ

Az Android `applicationId` a telepítés identitása. A megváltoztatása azt
jelenti, hogy egy olyan készüléken, amin már van korábbi (pre-rename) build:

- az új APK **külön appként** települ, a régi ikon mellé;
- a régi app **helyi adatai nem öröklődnek** — a `SharedPreferences` (streak,
  napi cél, gyakorlási napló, mentett dalok/setlistek, Library-felvételek,
  beállítások: téma, nyelv, capo, A4, bal kezes, Lab mode) az applicationId-hoz
  kötött privát tárolóban élnek;
- a `flutter_secure_storage`-ban tárolt JWT sem öröklődik → az opcionális
  fiókba **újra be kell jelentkezni** (a felhő-beállítások onnan visszatöltődnek);
- a mikrofon-engedélyt újra meg kell adni;
- a régi appot a felhasználó kézzel törölheti.

Ez az SDD szerint **elfogadható a publikus store release előtt**, és a projekt
még nincs store-ban. Nincs adatmigráció: egy pre-rename buildből az új buildbe
átvivő migrációt írni nagyobb kockázat és munka lenne, mint amennyit egy
egyfelhasználós, még nem publikált app helyi állapota ér.

**A userre gyakorolt gyakorlati hatás:** a valós-gitáros APK-teszt (a projekt
végső acceptance-kapuja) a következő buildtől friss appon fut — a korábbi
streak/gyakorlási előzmény a régi ikon alatt marad, amíg le nem törli.

## Visszavonhatóság

A rename tisztán mechanikus és teljesen visszafordítható a PR revertjével.
Ami **nem** fordul vissza: egy készülékre már feltelepített új app adatai nem
kerülnek át a régi applicationId alá.

## Kikényszerítés

`test/tooling/legacy_identifier_guard_test.dart` a `flutter test` gate része:
elhasal, ha bármelyik régi azonosító visszaszivárog production fájlba. A
történeti dokumentumok (`docs/`, `HANDOFF.md`) allowlisten vannak — azokat
visszamenőleg átírni történelemhamisítás lenne.
