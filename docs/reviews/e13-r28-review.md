# E13-R28 — Unified Library és Session Detail UI — review

- **Kör:** `E13-R28` · **Branch:** `sonnet-impl/e13-r28-unified-library`
- **Reviewelt HEAD:** `d20f310a` (a `1f9094ad` upstream-merge fölött)
- **Implementer motor:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Reviewer:** Claude (orchestrátor), read-only, izolált klón `/tmp/rev-e13-r28`
- **Előzmény:** az első futás **H3**-mal állt meg (§11 korábbi verdikt); a
  halt-ot a merge-elt önjavító kör (`8c48af55`, [L508](../LESSONS.md)) oldotta
  fel a brief §0.0/R5 revíziójával. Ez a review a **javító kör utáni**,
  teljes újramérés.
- **Verdikt:** ✅ **APPROVED** — 0 nyitott BLOCKER / MAJOR / MINOR.

---

## 1. Mit mértem, és min

Izolált klón a kör HEAD-jén (`d20f310a`), `tools/prepare-flutter-generated.sh`
után. A fa tiszta, az implementer jelzése `status=done`, `scope_audit=ok`
(`scope_audit_base=1f9094ad`, `scope_audit_changed=5`).

A `dirty_files=1` a jelzés pillanatában a **saját, menet közben írt
`.codex-round-status`** volt — a jelzés utáni `git status --short` a
munkapéldányon **üres** (0 fájl). Kivizsgálva, nem lelet (ADR 0087 §3
kötelező ellenőrzés).

## 2. A kötelező kapu — a SAJÁT futásom, csonkítatlanul

`/tmp/gate-rev-e13-r28.txt`, kilépési kód **0**:

| # | Lépés | Eredmény |
|---|---|---|
| 1 | format | **ZÖLD** |
| 2 | analyze | **ZÖLD** |
| 3 | `test/features/library_v2/item_routing_test.dart` | **ZÖLD** |
| 4 | `test/features/library_v2/corrupt_item_test.dart` | **ZÖLD** |
| 5 | `test/features/library_v2/delete_confirmation_test.dart` | **ZÖLD** |
| 6 | `test/features/library_v2/sync_conflict_test.dart` | **ZÖLD** |
| 7 | `test/features/library/` (befagyasztott V1 pinek) | **ZÖLD** |
| 8 | `test/app/navigation/` | **ZÖLD** |
| 9 | `test/app/routing/app_router_test.dart` (legacy route-pinek) | **ZÖLD** |
| 10 | `test/ui/goldens/e13_r28_screens_golden_test.dart` | **ZÖLD** |
| 11 | `test/ui/ui_inventory_test.dart` | **ZÖLD** |
| 12 | `test/core/architecture_dependency_test.dart` | **ZÖLD** *(az első futásban ez volt az EGYETLEN piros)* |
| 13 | `test/tooling/dio_factory_guard_test.dart` | **ZÖLD** |
| 14 | `test/tooling/preferences_plugin_import_guard_test.dart` | **ZÖLD** |
| 15 | `test/tooling/route_literal_guard_test.dart` | **ZÖLD** |
| 16 | architecture | **ZÖLD** |
| 17 | secrets | **ZÖLD** |
| 18 | l10n | **ZÖLD** |

**18/18 zöld.** Az első futás 12. lépésének pirosa lezárva.

## 3. A H3-lelet lezárása — mért, nem bemondott

### 3.1 A sértésszám 3 → 0

```
$ dart run tool/check_architecture.dart
Architecture dependencies OK (12 allowlisted deviation(s)).
```

A javítás PONTOSAN a §0.0/R5 mandátuma, se több:

- `lib/features/song_trainer/public.dart` — **tisztán additív** három
  export-sor, mind `show`-val szűkítve az öt nevesített szimbólumra
  (`SongQuery`, `SongRepository`, `SetlistRepository`,
  `songRepositoryProvider`, `setlistRepositoryProvider`). A meglévő két
  screen-export **érintetlen**.
- a három `library_v2` fájl importja (`song_item_source.dart`,
  `setlist_item_source.dart`, `library_v2_providers.dart`) a
  `../../song_trainer/public.dart` gyökér-barrelre állt át. Egyéb
  viselkedés-változás nincs — a diff kizárólag import-útvonal.

### 3.2 Valódi-sértés próba — a kapu ténylegesen érzékeny

A zöld önmagában nem bizonyíték, ezért falszifikáltam. A klónban
`song_item_source.dart` importját visszaírtam a belső útvonalra:

```
$ dart run tool/check_architecture.dart
Architecture dependency check failed.
Unexpected violation(s) — fix them; adding an allowlist entry requires justification and an ADR:
- lib/features/library_v2/data/song_item_source.dart -> lib/features/song_trainer/domain/repositories/song_repository.dart [cross-feature imports must target public.dart]
```

Kilépési kód **1**. A folt visszaállítva; a fa ismét tiszta. **A zöld tehát a
javításból jön, nem a mérce elnémulásából.**

### 3.3 A mércét nem kerülte meg

Gépileg ellenőrizve, hogy a kör diffje **nem** nyúlt az őrökhöz
(`git diff --quiet 8c48af55 d20f310a -- <útvonal>`):

- `tool/check_architecture.dart` — **változatlan** (nincs új allowlist-bejegyzés,
  ami ADR-t igényelt volna)
- `test/core/architecture_dependency_test.dart` — **változatlan**
- `tool/ui_inventory.dart` — **változatlan**
- `test/tooling/`, `test/features/library/`, `test/app/routing/app_router_test.dart` — **változatlan**

A §11 korábbi verdiktjében **C** ágként mért kerülőút (a wiring áthelyezése
`lib/app/routing/`-ba, ahol a `lib/app/**` mentesül a cross-feature szabály
alól) **nem** valósult meg: a wiring a `library_v2/providers/`-ben maradt.

## 4. Scope-audit — kézi újramérés

A kör teljes diffje az `origin/main` (`8c48af55`) ellen **38 fájl**, és
mindegyik az `allowed_paths` alatt van. A listán kívüli fájl: **nincs**.

A `allowed_paths`-on szereplő, de szándékosan szűk mandátumú fájlokat
tételesen megnéztem:

| Fájl | Mandátum | Mért diff |
|---|---|---|
| `test/ui/ui_inventory_test.dart` | §0.0/R4 — **PONTOSAN a szám emelése** | `hasLength(89)` → `hasLength(91)` + magyarázó komment. Más állítás (determinizmus, rendezettség, tartalmazás) **érintetlen**. ✅ |
| `test/app/navigation/adaptive_scaffold_test.dart` | §0.0/R3 — a lecserélt adapter TÍPUSA | egyetlen cella: `AppRoutes.profileLibrary: LibraryScreen` → `UnifiedLibraryScreen`. ✅ |
| `test/app/navigation/legacy_route_redirect_test.dart` | §0.0/R3 — a legacy redirect célja | egyetlen cella: `AppRoutes.library: LibraryScreen` → `UnifiedLibraryScreen`. ✅ |
| `lib/features/song_trainer/public.dart` | §0.0/R5 — öt szimbólum, `show`-val | három additív export-sor, a két screen-export érintetlen. ✅ |
| `lib/app/routing/` | §0.0/B2 — a `profileLibrary` builder + az új `profileLibrarySession` route | a `:264–265` (`AppRoutes.library` → `LibraryScreen`) és a `:305–313` (`librarySession` → `LibraryScreen`) builder **szó szerint érintetlen**. ✅ |

**Cella törlése, `skip`-je vagy küszöb-lazítása: nincs.** A `git diff` egyetlen
`skip:`-et vagy törölt `expect`-et sem tartalmaz a gate-őrökben.

### 4.1 Egy látszólagos ellentmondás, kimérve

A §10 A8-cellája azt állítja, hogy `AppRoutes.library` **változatlanul**
`LibraryScreen`-t épít — a `legacy_route_redirect_test.dart` pinje viszont
`UnifiedLibraryScreen`-re változott. Ez **nem** ellentmondás, és megmértem:

- `app_router.dart:264–265` — a `ShellRoute` alatti `GoRoute(path:
  AppRoutes.library)` buildere **szó szerint** `const LibraryScreen()` maradt;
- a redirect-teszt viszont nem ezt a buildert méri, hanem a
  `legacyRedirects[AppRoutes.library]` **cél**-útvonalát (`/profile/library`),
  amit ez a kör szándékosan migrált. A tesztfájl kommentje ezt pontosan
  ki is mondja.

A két állítás tehát két különböző mechanizmusra vonatkozik, és mindkettő igaz.
A pin-váltás pontosan az a kettő, amit a §0.0/R3 előre, írásban engedélyezett.

## 5. l10n — az aggregátum tényleg generált

A `lib/l10n/app_{en,hu}.arb` a listán **kizárólag generált kimenetként**
szerepel (§0.0/R1). Ellenőrizve: a klónban lefuttatva

```
dart run tool/gen_l10n_segments.dart --write
```

a fa **0 módosított fájllal** maradt — az aggregátum bitre reprodukálódik a
`base/` szegmensből, tehát nem kézzel írt. ✅

## 6. Leletek

| # | Súly | Lelet |
|---|---|---|
| — | — | **Nincs.** 0 BLOCKER, 0 MAJOR, 0 MINOR. |

**NOTE (nem lelet, nem blokkol):** a §10 „Nevesített follow-up" szakaszát a
javító kör helyesen elavultként átírta. A `song_trainer` barrel bővítése ezzel
megtörtént; további follow-up nem marad nyitva.

## 7. Verdikt

**APPROVED.** A kör kódja kész, a mérce 18/18 zöld a saját, izolált futásomon,
a korábbi EGYETLEN BLOCKER (H3) mért módon lezárva, a javítás falszifikációs
próbán átment, és a scope minden szűk mandátumú fájlon tételesen igazolt.
Merge a zöld exact-SHA CI-kapu (Full Gate + Router CI) után.
