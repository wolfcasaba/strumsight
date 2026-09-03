# Fixture: dátumozott jelentés őre — élő-fás pin vs. rögzített pillanatkép

**Forrás:** `test/ui/goldens/e15_r13_full_variant_matrix_test.dart` két
állapota, szó szerinti másolatban (semmilyen szerkesztés):

| Fájl | Honnan |
|---|---|
| `a5_guard_live_tree_pin.dart.txt` | az `A5 — completion-report guard` group `origin/main @ 70b5646558b83e88049879d7358ae71fe80ad157`-en — ez a **javítás előtti**, mérve piros alak |
| `a5_guard_recorded_baseline.dart.txt` | ugyanaz a group az ADR 0112 önjavító kör (`heal/E16-R02-H3-1`) javítása UTÁN |
| `a1_completeness_group.dart.txt` | az `A1 — completeness` group ugyanabból a fájlból — jogos ÉLŐ mérés, dátumozott jelentés nélkül (negatív kontroll) |

**Előállítás** (a group-blokkok a `group('A5 — completion-report guard` /
`group(\n    'A1 — completeness` kezdettől a záró `});` illetve `);` sorig,
karakterre pontosan kimásolva):

```bash
git show origin/main:test/ui/goldens/e15_r13_full_variant_matrix_test.dart   # a5_guard_live_tree_pin
cat test/ui/goldens/e15_r13_full_variant_matrix_test.dart                    # a5_guard_recorded_baseline, a1_completeness_group
```

## Miért `.txt` végződés

A pillanatkép NEM fordítandó forrás (a group-blokk önmagában nem is érvényes
Dart fájl). A `.txt` tartja távol a Dart-kapuktól (`dart format
--set-exit-if-changed lib test tool`, `flutter analyze lib/ test/ tool/`) és
mondja ki ránézésre, hogy ez rögzített bemenet, nem élő kód. Ugyanaz a
konvenció, mint a `fixtures/e16_r02_route_level_swap/`-nál.

## Miért létezik ez a fixture (MÉRT ok, ADR 0112 önjavító kör, 2026-09-03)

Az E16-R02 / 4. H3 gyökéroka: az `A5` cella az ÉLŐ fából mérte újra a
reachability-t (`ScreenReachability(Directory.current).render()`), és attól
követelte meg egy **dátumozott** jelentés
(`docs/ui/chapter-15-completion-report.md`, fejléc: „Measured against: `main @
9ba54399` + this round's own tree") szám-egyezését. Az E16-R02 acceptance-
kritériuma pontosan két képernyő elérhetővé tétele, tehát `reachableCount`
71 → 73 — a kör **sikere** vitte pirosra a full-gate-et
(run `33808412804`, SHA `73ff5351`), miközben a jelentés és az őrteszt is a
kör TILOS zónájában van, tehát a kör-session nem is javíthatta.

A szabályt mérő cellák ezért rögzített bemenetből dolgoznak: ha az élő fát
olvasnák, a javított kör saját kódja mozdítaná el alóluk a mércét — pontosan
az a hibaosztály, amit ez a guard tilt (L612, L613).

**Ez nem gyengítés.** Az élő fát a `test_no_dart_test_pins_a_dated_report_to_
the_live_tree` cella járja végig — az a KÖVETELT VÉGÁLLAPOTOT pinneli (nulla
lelet a teljes `test/` fán), amit csak a hibaosztály újbóli bevezetésével lehet
pirosra vinni.
