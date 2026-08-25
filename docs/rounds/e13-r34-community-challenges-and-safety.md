# E13-R34 — Community challenges, clubs, notifications és safety UI

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ 0f7afd9a`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 34
- **Kör-azonosító:** `E13-R34`
- **Branch:** `<motor>/e13-r34-community-challenges-and-safety`
- **Előfeltétel:** `E13-R33` merge-elve (közösségi feed és posztok)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — az ADR 0291 (opcionális, alapból privát) érvényes.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd el a TÉNYLEGES kihívás- és
> moderációs szerződéseket, kiemelten a „függő" (pending) vs. „ellenőrzött"
> (verified) állapotot — a §5.2 cella erre a mért megkülönböztetésre épül.
> Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/community/challenges/",
  "lib/features/community/clubs/",
  "lib/features/community/safety/",
  "lib/l10n/features/community_en.arb",
  "lib/l10n/features/community_hu.arb",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/community/challenge_join_test.dart",
  "test/features/community/leaderboard_optin_test.dart",
  "test/features/community/private_club_leakage_test.dart",
  "test/features/community/notification_deeplink_test.dart",
  "test/ui/goldens/",
  "test/ui/ui_inventory_test.dart",
  "docs/rounds/e13-r34-community-challenges-and-safety.md",
]
gate_tests = [
  "test/features/community/challenge_join_test.dart",
  "test/features/community/leaderboard_optin_test.dart",
  "test/features/community/private_club_leakage_test.dart",
  "test/features/community/notification_deeplink_test.dart",
  "test/ui/goldens/e13_r34_screens_golden_test.dart",
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

**Kockázat = high, indoklás:** a challenge/klub/safety felületek moderációs és jelentési műveleteket indítanak idegen tartalom felett.

### R1 — `lib/l10n/app_{en,hu}.arb` GENERÁLT aggregátum → a FORRÁS a szegmens

A kör fájából `lib/features/community/challenges/`, `lib/features/community/clubs/`, `lib/features/community/safety/` **még nem létezik** — a képernyőket ez a kör hozza létre, tehát MINDEN szövege új.

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
EGZAKT `hasLength(...)`-et állít rájuk. Ez a kör a(z) `lib/features/community/challenges/`, `lib/features/community/clubs/`, `lib/features/community/safety/` könyvtár-előtag
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

Az UI-59–UI-61 kihívás-, ranglista-, klub-, értesítés- és biztonsági felületei
(SDD Ch13 Kör 34).

## 2. Jelenlegi állapot — mért tények

- Az R33 lefektette az opcionális, alapból privát közösségi alapot — ez a kör
  ugyanezt viszi tovább a versengő felületekre.
- A kihívás-eredmény **függő** és **ellenőrzött** állapota két különböző dolog.
- A privát klub tartalma a legkönnyebben szivárgó adat (előnézet, értesítés,
  mély hivatkozás).

## 3. Scope

**Benne van:** a kihívás listája és részletnézete, csatlakozás-megerősítés,
ellenőrzés és ranglista · a klubok nyilvános / privát / csatlakozási kérelem /
tag / moderátor / archivált állapotai · az értesítések és a Biztonsági központ
lista-részlet felülete · tiltott/némított lista, bejelentés-státusz és
értesítés-beállítások · **semleges** microcopy az integritás-vizsgálathoz ·
lapozás, offline gyorsítótár, mély hivatkozás validálása és jogosultsági
tesztek.

**NINCS benne (tilos):** a moderációs vagy anti-cheat logika módosítása · a
ranglista alapértelmezett bekapcsolása · más képernyők · `docs/adr/**`,
`tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `community/challenges/` | kihívás és ranglista |
| `community/clubs/` | klubok |
| `community/safety/` | értesítések és biztonsági központ |
| `lib/l10n/features/community_{en,hu}.arb` | **FORRÁS** — a szövegek (`community` MÁR migrált feature) |
| `lib/l10n/app_{en,hu}.arb` | **CSAK GENERÁLT KIMENET** — kizárólag `dart run tool/gen_l10n_segments.dart --write`, kézzel írni TILOS |
| `test/features/community/*_test.dart` (4) | a §6 cellái |
| `test/ui/ui_inventory_test.dart` | **repó-szintű képernyő-leltár őr** — a kör új `lib/features/**/*_screen.dart`-ot hozhat, ezért az egzakt `hasLength(...)` elmozdul; a jogosultság PONTOSAN a szám emelése, más állítás nem érinthető (§0.0/R4) |
| `docs/rounds/e13-r34-…md` | a §10 handoff |

**Tilos zóna:** `lib/features/community/` a három érintett almappán kívül ·
`lib/features/**` egyébként · `lib/core/design_system/**` · `docs/adr/**` ·
`docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések

### 5.1 A ranglista OPT-IN

A felhasználó nem kerül rá automatikusan azzal, hogy gyakorol. A versengés
választás, nem alapállapot (az ADR 0291 §2 kiterjesztése).

**NEM elfogadható gyengítés:** automatikus felvétel a ranglistára a kihíváshoz
csatlakozáskor. A csatlakozás nem egyenlő a nyilvános rangsorolás vállalásával.

### 5.2 A függő bejegyzés NEM ellenőrzött

A két állapot vizuálisan és szövegesen is elkülönül. Az ellenőrizetlen eredmény
nem jelenik meg véglegesként.

### 5.3 A privát klub tartalma NEM szivárog

Sem előnézetben, sem értesítésben, sem mély hivatkozáson át. Ez
acceptance-cella (A3), és a kör legfontosabb invariánsa.

**NEM elfogadható gyengítés:** „a cím megjelenítése ártalmatlan az
értesítésben". A cím maga is tartalom.

### 5.4 A mély hivatkozás VALIDÁLT

Az értesítésből érkező link jogosultság-ellenőrzésen megy át, mielőtt bármit
megjelenítene. Nem megbízható bemenet.

### 5.5 Az integritás-vizsgálat microcopyja SEMLEGES

A vizsgálat alatt álló eredmény nem vádol csalással. A semleges szöveg tényt
közöl, nem ítéletet.

### 5.6 A biztonsági akció ELÉRHETŐ, nem elrejtett

Bejelentés, tiltás és némítás minden releváns felületről elérhető, nem csak a
beállításokból.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A ranglistára kerülés opt-in, csatlakozásból nem következik | `leaderboard_optin_test.dart` |
| A2 | A függő bejegyzés vizuálisan és szövegesen elkülönül az ellenőrzöttől | `challenge_join_test.dart` |
| A3 | A privát klub tartalma nem szivárog (előnézet, értesítés, mély link) | `private_club_leakage_test.dart` |
| A4 | A mély hivatkozás jogosultság-ellenőrzésen megy át | `notification_deeplink_test.dart` |
| A5 | Az integritás-vizsgálat szövege semleges (en + hu) | `challenge_join_test.dart` |
| A6 | A biztonsági akciók a releváns felületekről elérhetők | `private_club_leakage_test.dart` |
| A7 | A ranglista lapozása stabil, nem duplikál és nem hagy ki | `leaderboard_optin_test.dart` |
| A8 | A tiltás/némítás állapota a felületek között egységes | ugyanott |
| A9 | A kör §3-ban megnevezett MINDEN képernyőről golden-felvétel készül és be van commitolva — 412×915 compact portrait ÉS `textScaleFactor: 2.0` | `e13_r34_screens_golden_test.dart` + a `test/ui/goldens/*.png` a diffben |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A csatlakozás automatikusan ranglistára tesz | **A1** |
| A függő eredmény véglegesként | **A2** |
| A privát klub címe az értesítésben | **A3** |
| A mély link ellenőrzés nélkül nyit tartalmat | **A4** |
| „Csalás gyanúja" szöveg a vizsgálatnál | A5 |
| A lapozás ismétli az utolsó elemet | A7 |
| A képernyő elcsúszik, túlcsordul vagy nagy szövegméretnél olvashatatlan | **A9** |

**A klub-láthatóság három kötelező cellája** (a küszöb: a felhasználó tagsága):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | nem tag, privát klub | **semmilyen tartalom** — csak a létezés és a csatlakozási út |
| rajta (a küszöbön) | **függő csatlakozási kérelem** | továbbra sincs tartalom — a kérelem állapota látszik |
| a küszöb fölött | elfogadott tag | teljes tartalom |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** jelenítsd meg a privát
klub címét egy értesítésben nem tagnak → az **A3** cellának PIROSNAK kell
lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/community/challenge_join_test.dart test/features/community/leaderboard_optin_test.dart test/features/community/private_club_leakage_test.dart test/features/community/notification_deeplink_test.dart test/ui/goldens/e13_r34_screens_golden_test.dart test/ui/ui_inventory_test.dart test/core/architecture_dependency_test.dart test/tooling/dio_factory_guard_test.dart test/tooling/preferences_plugin_import_guard_test.dart test/tooling/route_literal_guard_test.dart
```

**A golden-felvétel (A9) rögzítése — a mérce ÚJ, nem alku tárgya:** a képernyő
minden állapotát NEM kell felvenni, a §3 szerinti alap-nézet elég, de a két
keret (412×915 compact portrait és ugyanaz `textScaleFactor: 2.0` mellett)
KÖTELEZŐ. Minta és futó precedens: `test/features/live/chord_timeline_golden_test.dart`
(valódi kapu, nem `skip`-elt rögzítő). Előállítás:

```bash
~/flutter/bin/flutter test --update-goldens test/ui/goldens/e13_r34_screens_golden_test.dart
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

> **Review-megjegyzés:** ez a kör jogosultsági határt és nyilvános adatot
> érint, ezért a review-ban a `security-reviewer` ügynök futtatása kötelező.

## 8. Implementációs sorrend

1. A kihívás listája és részletnézete, csatlakozás-megerősítéssel.
2. A ranglista opt-in kapcsolója + a lapozás stabilitása.
3. A függő/ellenőrzött megkülönböztetés és a semleges vizsgálat-szöveg.
4. A klub-állapotok + a három láthatósági cella.
5. Az értesítések és a mély hivatkozás jogosultság-ellenőrzése.
6. A Biztonsági központ: tiltott/némított lista, bejelentés-státusz.
7. A valódi-sértés próba, §10-be dokumentálva.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A privát klub szivárgása.** Több csatornán is előfordulhat (előnézet,
  értesítés, mély link), és mindegyiket külön kell zárni (A3).
- **Az automatikus ranglista.** Kényelmesnek látszik, és nyilvános
  összehasonlításba kényszeríti a felhasználót (A1).
- **A vádaskodó vizsgálat-szöveg.** Ártatlan felhasználót bélyegez meg egy
  automatikus jelzés miatt (A5).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
