# E13-R33 — Community profil, feed, keresés és poszt UI

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ 0f7afd9a`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 33
- **Kör-azonosító:** `E13-R33`
- **Branch:** `<motor>/e13-r33-community-feed-and-posts`
- **Előfeltétel:** `E13-R32` merge-elve (gamifikáció)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`0291`](../adr/0291-community-is-optional-and-private-by-default.md)
  — **a Claude írja meg a kör indításakor; a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd el a TÉNYLEGES közösségi
> domain-t és a poszt-küldés idempotencia-kulcsát — a §5.5 kimondja, hogy az
> újrapróbálkozás nem duplikálhat. Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/community/profile/",
  "lib/features/community/feed/",
  "lib/features/community/posts/",
  "lib/l10n/features/community_en.arb",
  "lib/l10n/features/community_hu.arb",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/community/community_gate_test.dart",
  "test/features/community/composer_audience_test.dart",
  "test/features/community/offline_publish_retry_test.dart",
  "test/features/community/block_mute_test.dart",
  "test/ui/goldens/",
  "test/ui/ui_inventory_test.dart",
  "docs/rounds/e13-r33-community-feed-and-posts.md",
]
gate_tests = [
  "test/features/community/community_gate_test.dart",
  "test/features/community/composer_audience_test.dart",
  "test/features/community/offline_publish_retry_test.dart",
  "test/features/community/block_mute_test.dart",
  "test/ui/goldens/e13_r33_screens_golden_test.dart",
  "test/ui/ui_inventory_test.dart",
  "test/core/architecture_dependency_test.dart",
  "test/tooling/dio_factory_guard_test.dart",
  "test/tooling/preferences_plugin_import_guard_test.dart",
  "test/tooling/route_literal_guard_test.dart",
]
native_gate = false
```

## 0.0 BRIEF-REVÍZIÓ — 2026-08-25, batch pre-flight (E13-R17…R35)

A brief 2026-08-15-én készült; ez a pre-flight `main @ 41fbd40` ellen mért.
**Visszakeresett előzmény:** [L478](../LESSONS.md) (a pre-flight csak szűkíthet;
a tágítás H3), [ADR 0307 §4](../adr/0307-parallel-round-execution.md) (a
`lib/l10n/app_*.arb` GENERÁLT aggregátum, a forrás a `base/` és a
`features/` szegmens), [L481](../LESSONS.md) (a lánc remote konténerből nem
indítható). A hibaosztályt a **teljes Ch13 sávon** mérte ki egy batch-vizsgálat:
az R17–R35 MIND a generált aggregátumot sorolta fel forrásként (`agg=2, frag=0`).

**Kockázat = high, indoklás:** a közösségi feed IDEGEN felhasználók tartalmát rendereli — prompt-injection és megbízhatatlan-tartalom felület.

### R1 — `lib/l10n/app_{en,hu}.arb` GENERÁLT aggregátum → a FORRÁS a szegmens

A kör fájából `lib/features/community/profile/`, `lib/features/community/feed/`, `lib/features/community/posts/` **még nem létezik** — a képernyőket ez a kör hozza létre, tehát MINDEN szövege új.

A kör ezért **nem tudott volna egyetlen szöveget sem írni** a saját listáján
belül. Feloldás — H3 lista-tágítás, **user-engedéllyel (2026-08-25)**, a
lehető legszűkebb alakban:

- `community` → a MÁR LÉTEZŐ `features/community_*.arb` fragmentum

Az aggregátum a listán MARAD, de **kizárólag generált kimenetként**
(`dart run tool/gen_l10n_segments.dart --write`); a merge-elt precedens
egységesen a forrást ÉS a regenerált aggregátumot is commitolja (E09-R26
`df0ad3dd`, E13-R12 `376b8a1d`, E13-R10 `b11ab2ed`). **Új fragmentum NEM
készül**, ezért a `test/l10n/arb_parity_test.dart` beégetett szegmens-listáját
sem kell bővíteni — a felvett források mind szerepelnek benne.

### R2 — a kör SAJÁT feature-fáján élő, ma zöld widget-tesztek (FELVÉVE)

Ezek közvetlenül a migrálandó képernyőkre állítanak, tehát a migráció után
pirosra váltanának, ami a §0 szerint `blocked` lenne:

  - nincs ilyen.

**A jogosultság szűk:** a teszteket az ÚJ widgetekre kell ráállítani. A lefedett
viselkedést gyengíteni, cellát törölni vagy `skip`-elni **TILOS** — az a mérce
meggyengítése, amit a gate-guard emberhez eszkalál.

### R3 — keresztmetszeti tesztek (NEM kerültek listára — figyelmeztetés)

A kör fájára hivatkozó további widget-tesztek közös infrastruktúrán élnek
(`test/app/**`, `test/core/**`, más feature-ek fái) — nincs ilyen. Ezeket a kör
**NEM** szerkesztheti: ha egy elbukik, az `blocked` jelzés és célzott
brief-revízió, nem csendes átírás. A körbe húzásuk a scope-fegyelem feladása
lenne.

### R4 — a képernyő-leltár őre (H3 önjavító kör, ADR 0112, 2026-08-25)

A `test/ui/ui_inventory_test.dart` **repó-szintű** őr: a `tool/ui_inventory.dart`
a `lib/features/**` fa `_screen.dart` végű fájljait számolja, a teszt pedig
EGZAKT `hasLength(...)`-et állít rájuk. Ez a kör a(z) `lib/features/community/feed/`, `lib/features/community/posts/`, `lib/features/community/profile/` könyvtár-előtag
alá képernyőt hoz vagy hozhat, tehát a szám **elmozdul**, és az exact-SHA Full
Gate pirosra vált.

A `test/ui/goldens/` előtag ezt **nem** fedi (az a `test/ui/` fának csak az egyik
ága), a leltárteszt utólagos felvétele pedig tágítás, azaz **H3** — az
orchestrátor a pre-flightban nem oldhatja fel ([L478](../LESSONS.md)). Ezért
kerül a listára MOST, az önjavító körben.

**MÉRVE (E13-R16, 2026-08-25):** pontosan ez a hiány állította meg a sáv első
migrációs körét — [full-gate 32867296946](https://github.com/wolfcasaba/strumsight/actions/runs/32867296946)
6366 passed / 2 failed, `hasLength(79)` a tényleges 81 ellen. A `9acd14e5`
sáv-szintű batch pre-flight azért nem találta meg, mert a `tools/brief-lint.py`
`S9` szabálya csak LITERÁLIS `*_screen.dart` útvonalat nézett, KÖNYVTÁR-előtagot
nem — a predikátumot ugyanez az önjavító kör javította, regressziós teszttel
([L483](../LESSONS.md)).

**A jogosultság PONTOSAN a szám emelése** a kör tényleges képernyőszámára; a
leltárteszt minden más állítása érintetlen marad. Kerülőút (képernyő-átnevezés
vagy a `tool/ui_inventory.dart` szabályának lazítása) **TILOS** — az a mérce
meghamisítása.

### S12 — a fa-szintű őrök a kör LOKÁLIS kapujába (2026-08-25)

A kör lokális kapuja eddig KIZÁRÓLAG a saját céltesztjeit futtatta, ezért a
teljes `lib/` fát pásztázó őrök leletei szerkezetileg csak a ~17 perces
exact-SHA Full Gate-en jelentek meg — javító kör árán. MÉRT eset: **E13-R16/F8**
(`docs/reviews/e13-r16-review.md`), ahol mind a három új képernyő közvetlenül
importálta a `design_system/foundations/**`-ot a `public.dart` helyett — **11
sértés** —, és a review szó szerint rögzíti, miért nem fogta a célzott gate:
a `tools/round-gate.sh` `architecture` lépése a `tool/check_architecture.dart`-ot
futtatja, ami egy MÁSIK, tágabb szabálykészlet; a design-system-határ mércéje
egy külön `test/core/` teszt, amit csak a teljes suite futtat.

Ezért ez a kör mostantól a `gate_tests`-ben futtatja ezeket az őröket:

- `test/core/architecture_dependency_test.dart`
- `test/tooling/dio_factory_guard_test.dart`
- `test/tooling/preferences_plugin_import_guard_test.dart`
- `test/tooling/route_literal_guard_test.dart`

A kiválasztás MÉRT, nem vaktában: a globális őrök a `Directory('lib')` teljes
fát pásztázzák (bármelyik kör diffje elmozdíthatja őket), a szűkített őrök pedig
csak akkor kerülnek fel, ha a kör `allowed_paths`-a metszi a pásztázott
gyökeret.

**Ezek az őrök NEM kerülnek az `allowed_paths`-ra** — és ez szándékos: a kör
futtatja, de NEM szerkesztheti őket, tehát a lelet javítása kizárólag a kör
SAJÁT kódjában történhet. Cella törlése, `skip`-je vagy küszöb-lazítása így
gépileg kizárt, a mérce pedig tiszta erősítést kap.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 1. Cél

Az UI-53–UI-58 **opcionális** közösségi felületei: belépő, feed, felfedezés,
profil, szerkesztő és beszélgetés (SDD Ch13 Kör 33).

## 2. Jelenlegi állapot — mért tények

- A közösségi funkció **opcionális**: a termék magja nélküle is teljes.
- Az R13 megerősítés-rendszere és az R12 provenance-badge-ei készen állnak.
- A gyakorlási adat a felhasználó legszemélyesebb tartalma — a megosztása
  soha nem lehet implicit.

## 3. Scope

**Benne van:** a közösségi belépő és a nyilvános profil beállítása
**alapból priváttal** · a feed tartalmi / offline / eltávolított / moderációs
állapotai · keresés és felfedezés, nyilvános profil kapcsolat- és
biztonsági akcióival · a poszt-szerkesztő közönség-, csatolmány-,
gyakorlás-megosztás és offline sor felülete · a poszt részletnézete, reakciók,
kommentek, szál-állapotok · a tiltás/némítás **azonnali helyi szűrése**.

**NINCS benne (tilos):** a moderációs vagy a backend-logika módosítása · az
idempotencia-kulcs megjelenítése a felületen · a közösség kötelezővé tétele ·
`docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `community/profile/` | belépő és nyilvános profil |
| `community/feed/` | feed és felfedezés |
| `community/posts/` | szerkesztő és beszélgetés |
| `lib/l10n/features/community_{en,hu}.arb` | **FORRÁS** — a közösségi szövegek (`community` MÁR migrált feature) |
| `lib/l10n/app_{en,hu}.arb` | **CSAK GENERÁLT KIMENET** — kizárólag `dart run tool/gen_l10n_segments.dart --write`, kézzel írni TILOS |
| `test/features/community/*_test.dart` (4) | a §6 cellái |
| `test/ui/ui_inventory_test.dart` | **repó-szintű képernyő-leltár őr** — a kör új `lib/features/**/*_screen.dart`-ot hozhat, ezért az egzakt `hasLength(...)` elmozdul; a jogosultság PONTOSAN a szám emelése, más állítás nem érinthető (§0.0/R4) |
| `docs/rounds/e13-r33-…md` | a §10 handoff |

**Tilos zóna:** `lib/features/**` a `community/` három almappáján kívül ·
`lib/core/design_system/**` · `docs/adr/**` · `docs/sdd/**` · `tools/**` ·
`.github/**`.

## 5. Kötött architekturális döntések (ADR 0291)

### 5.1 A termék magja közösség NÉLKÜL is teljes

Semmilyen alapfunkció nem követel fiókot vagy nyilvános profilt. A belépő
elutasítása nem zár ki semmit.

### 5.2 Az alapértelmezett közönség NEM nyilvános

Sem a profil, sem a poszt. A nyilvánosságot a felhasználó választja, tudatosan.

**NEM elfogadható gyengítés:** a „Nyilvános" előre kiválasztott közönség „mert
úgyis azt akarják". Ez visszavonhatatlan megosztást eredményez félrekattintásból.

### 5.3 A nyers gyakorlási adat NEM megy implicit módon

Ha egy poszt gyakorlási eredményt oszt meg, a felület megmutatja, **pontosan
mi** kerül ki, és a nyers hang alapból nem tartozik bele.

### 5.4 A tiltás AZONNAL hat, helyben is

Nem kell megvárni a szerver megerősítését ahhoz, hogy a tartalom eltűnjön a
felhasználó képernyőjéről.

### 5.5 Az újrapróbálkozás NEM duplikál posztot vagy kommentet

Az offline sor idempotencia-kulcsot használ. A kulcs a **transzportban** él, a
felületen nem jelenik meg.

**NEM elfogadható gyengítés:** „a felhasználó úgyis látja, ha kétszer ment el".
Egy duplikált poszt nyilvános és kínos, egy duplikált komment zajos.

### 5.6 Az eltávolított tartalom HELYŐRZŐT kap

Nem tűnik el némán a szálból — a beszélgetés érthető marad.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A termék magja közösség nélkül teljesen működik | `community_gate_test.dart` |
| A2 | Az alapértelmezett közönség nem nyilvános (profil és poszt) | `composer_audience_test.dart` |
| A3 | A gyakorlás-megosztás megmutatja, pontosan mi kerül ki | ugyanott |
| A4 | A nyers hang alapból nem része a megosztásnak | ugyanott |
| A5 | A tiltás/némítás azonnal, helyben is hat | `block_mute_test.dart` |
| A6 | Az újrapróbálkozás nem duplikál posztot vagy kommentet | `offline_publish_retry_test.dart` |
| A7 | Az eltávolított tartalom helyőrzőt kap | `community_gate_test.dart` |
| A8 | A felhasználónév-validáció hibás bevitelt nem enged tovább | ugyanott |
| A9 | A kör §3-ban megnevezett MINDEN képernyőről golden-felvétel készül és be van commitolva — 412×915 compact portrait ÉS `textScaleFactor: 2.0` | `e13_r33_screens_golden_test.dart` + a `test/ui/goldens/*.png` a diffben |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A „Nyilvános" előre kiválasztva | **A2** |
| A gyakorlás-megosztás nem sorolja fel a tartalmat | **A3** |
| A nyers hang alapból csatolva | **A4** |
| A tiltás csak szerver-válasz után hat | **A5** |
| Az offline sor kulcs nélkül próbálkozik újra | **A6** |
| Az eltávolított komment némán eltűnik | A7 |
| A képernyő elcsúszik, túlcsordul vagy nagy szövegméretnél olvashatatlan | **A9** |

**A közönség-alapérték három kötelező cellája** (a küszöb: a láthatóság szintje):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | új felhasználó, nincs választás | **privát** — ez az alapérték |
| rajta (a küszöbön) | a felhasználó „követők" közönséget választ | a választás érvényesül és látszik a küldés előtt |
| a küszöb fölött | a felhasználó „nyilvános"-t választ | **kimondott megerősítés** a visszavonhatatlanságról |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** állítsd az
alapértelmezett közönséget nyilvánosra → az **A2** cellának PIROSNAK kell
lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/community/community_gate_test.dart test/features/community/composer_audience_test.dart test/features/community/offline_publish_retry_test.dart test/features/community/block_mute_test.dart test/ui/goldens/e13_r33_screens_golden_test.dart test/ui/ui_inventory_test.dart test/core/architecture_dependency_test.dart test/tooling/dio_factory_guard_test.dart test/tooling/preferences_plugin_import_guard_test.dart test/tooling/route_literal_guard_test.dart
```

**A golden-felvétel (A9) rögzítése — a mérce ÚJ, nem alku tárgya:** a képernyő
minden állapotát NEM kell felvenni, a §3 szerinti alap-nézet elég, de a két
keret (412×915 compact portrait és ugyanaz `textScaleFactor: 2.0` mellett)
KÖTELEZŐ. Minta és futó precedens: `test/features/live/chord_timeline_golden_test.dart`
(valódi kapu, nem `skip`-elt rögzítő). Előállítás:

```bash
~/flutter/bin/flutter test --update-goldens test/ui/goldens/e13_r33_screens_golden_test.dart
```

A keletkezett PNG-ket **commitolni kell** — enélkül az A9 nem teljesült. A
márkabetűtípusok a teszt-hostban nem töltődnek be (fallback face); ez a
meglévő golden-teszt mért viselkedése, az elrendezést, méretezést és színeket
nem érinti. MIÉRT ez a kör dolga és nem az E13-R36-é: a záró vizuális
regressziós kör csak azt tudja megmondani, hogy valami MEGVÁLTOZOTT — azt,
hogy a képernyő eleve csúnya-e, a saját körében kell látni.

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

> **Review-megjegyzés:** ez a kör nyilvános megosztást és felhasználói adatot
> érint, ezért a review-ban a `security-reviewer` ügynök futtatása kötelező.

## 8. Implementációs sorrend

1. A közösségi belépő — a mag működése nélküle is.
2. A nyilvános profil beállítása, alapból priváttal + a három közönség-cella.
3. A feed állapotai, eltávolított tartalom helyőrzővel.
4. A poszt-szerkesztő: közönség, csatolmány, gyakorlás-megosztás tételesen.
5. Az offline sor idempotencia-kulccsal (a felületen nem látszik).
6. A tiltás/némítás azonnali helyi szűrése.
7. A valódi-sértés próba, §10-be dokumentálva.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **Az előre kiválasztott nyilvános közönség.** Egyetlen félrekattintásból
  visszavonhatatlan megosztás lesz (A2).
- **A duplikált poszt.** Az offline sor legkézenfekvőbb hibája, és nyilvánosan
  látszik (A6).
- **A késleltetett tiltás.** A felhasználó továbbra is látja azt, akitől épp
  védekezni próbál (A5).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
