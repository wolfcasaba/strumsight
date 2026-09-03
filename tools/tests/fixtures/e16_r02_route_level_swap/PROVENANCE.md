# Fixture: E16-R02 útvonal-szintű képernyőcsere (halt-pillanat)

**Forrás:** `origin/main @ 4fffa3f1e268a18120ac897feeb0d7e7bc886012` (2026-09-03),
vagyis az a fa, amelyen az E16-R02 kör MÉG NEM landolt, és amelyen a
`tools/tests/test_brief_lint_route_level_screen_swap.py` **mérve zöld volt**
(`python3 -m pytest tools/tests/test_brief_lint_route_level_screen_swap.py -q`
→ `6 passed`).

**Előállítás (szó szerinti másolat, semmilyen szerkesztés):**

```bash
FX=tools/tests/fixtures/e16_r02_route_level_swap
cp lib/app/routing/app_router.dart                   $FX/lib/app/routing/app_router.dart.txt
cp lib/app/routing/app_route.dart                    $FX/lib/app/routing/app_route.dart.txt
cp test/app/offline_network_guard_test.dart          $FX/test/app/offline_network_guard_test.dart.txt
cp test/app/routing/app_router_test.dart             $FX/test/app/routing/app_router_test.dart.txt
cp test/features/today/hub_navigation_test.dart      $FX/test/features/today/hub_navigation_test.dart.txt
cp test/features/progress/progress_screen_test.dart  $FX/test/features/progress/progress_screen_test.dart.txt
cp test/core/screen_size_guard_test.dart             $FX/test/core/screen_size_guard_test.dart.txt
cp docs/rounds/e16-r02-progress-projection-and-router-placeholders.md \
   $FX/docs/rounds/e16-r02-progress-projection-and-router-placeholders.md.txt
```

## Miért `.txt` végződés

A pillanatkép NEM fordítandó forrás. A `.txt` tartja távol a Dart-kapuktól
(`dart format --set-exit-if-changed lib test tool`, `flutter analyze lib/ test/
tool/`) és mondja ki ránézésre, hogy ez rögzített bemenet, nem élő kód. A
`_materialise_fixture()` a `.txt`-t levágva írja ki egy `tempfile`-be, tehát a
lint pontosan az eredeti fájlneveket látja.

## Miért létezik ez a fixture (MÉRT ok, ADR 0112 önjavító kör, 2026-09-03)

Az E16-R02 / H3 halt gyökéroka: ez a guard az **ÉLŐ fát és az ÉLŐ briefet**
olvasta, és a saját köre MUNKÁJÁNAK HIÁNYÁT pinnelte. Ettől a kör **sikere**
vitte pirosra a Router CI-t — a kör terméke hibátlan volt (célzott kapu 21/21,
Full Gate zöld a `c2b1362a` SHA-n), mégis a saját őre zárta ki a merge-ből.

Két mért mechanizmus vitte pirosra:

1. **Az élő fa.** A kör az `/profile/progress` `GoRoute.builder`-ét a legacy
   `ProgressScreen`-ről a `ProgressDashboardScreen`-re köti át, ezért a
   `route_level_swapped_screens()` a kör HEAD-jén már nem a
   `progress_screen.dart`-ot adja vissza.
2. **Az élő brief.** A kör a §10-be beírta a saját review-leletét, amely
   szó szerint tartalmazza a `/profile/library` útvonalat
   (`docs/rounds/…-placeholders.md:659`, MINOR-4). A brief-szűrő ettől a
   `unified_library_screen.dart`-ot is „lecserélhető képernyőnek" látja, és az
   S11 egy vadonatúj leletet ad — a kör SAJÁT dokumentációjától.

   ```
   main brief:       grep -c "/profile/library" … → 1
   kör HEAD briefje: grep -c "/profile/library" … → 2
   ```

A guard *szabály-viselkedést* bizonyít (a `brief-lint` S11/S14 szűrői helyesen
válogatnak), nem a fa aktuális állapotát — tehát a helyes bemenete a rögzített
halt-pillanat, nem a tovább fejlődő fa.

**Ez nem gyengítés.** Az élő fán futó, kimerítő mérést a Router CI
`brief-lint.py --open --level base` lépése végzi, amely szándékosan CSAK a még
NYITOTT körök briefjeit linteli (`.github/workflows/router-ci.yml`: „a merge-elt
körök briefje történeti rekord, azt visszamenőleg nem linteljük"). Egy merge-elt
kör briefjét az élő fához mérni éppen az a dolog, amit a termelési lint nem
csinál.

## A képernyő-fájlokról

A `_router_screen_files()` a router import-jaiból KIZÁRÓLAG az útvonalat
használja (`files[_dart_type_name_guess(stem)] = relative`), a fájl tartalmát
soha nem olvassa — csak a létezését ellenőrzi (`is_file()`). Ezért a
materializáló a fixture routerének SAJÁT import-listájából, gépiesen hoz létre
egy-egy üres fájlt. Kitalált tartalom nincs benne.
