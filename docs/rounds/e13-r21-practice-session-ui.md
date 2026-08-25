# E13-R21 — Practice setup és aktív session UI

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ e9a2c8b2`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 21
- **Kör-azonosító:** `E13-R21`
- **Branch:** `<motor>/e13-r21-practice-session-ui`
- **Előfeltétel:** `E13-R20` merge-elve (tanulási felületek)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — az ADR 0276/0279 érvényes erre a körre.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd el a TÉNYLEGES gyakorlási
> állapotgépet (`lib/features/practice/`) — a §5.1 kimondja, hogy a widget nem
> tárol üzleti állapotot, tehát a UI ehhez az állapotgéphez kapcsolódik, nem
> mellé épít. Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/practice/",
  "lib/l10n/base/app_en.arb",
  "lib/l10n/base/app_hu.arb",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/practice/presentation/chord_change_view_test.dart",
  "test/features/practice/presentation/chord_progression_view_test.dart",
  "test/features/practice/presentation/free_practice_view_test.dart",
  "test/features/practice/presentation/practice_a11y_audit_test.dart",
  "test/features/practice/presentation/practice_highway_scaling_test.dart",
  "test/features/practice/presentation/practice_highway_test.dart",
  "test/features/practice/presentation/practice_hub_screen_test.dart",
  "test/features/practice/presentation/practice_result_screen_test.dart",
  "test/features/practice/presentation/practice_routing_test.dart",
  "test/features/practice/presentation/practice_session_lifecycle_test.dart",
  "test/features/practice/presentation/practice_session_screen_test.dart",
  "test/features/practice/presentation/practice_setup_screen_test.dart",
  "test/features/practice/presentation/practice_vision_dimension_test.dart",
  "test/features/practice/presentation/rhythm_only_view_test.dart",
  "test/features/practice/presentation/speed_builder_progress_test.dart",
  "test/features/practice/presentation/strum_pattern_view_test.dart",
  "test/features/practice/presentation/timing_bias_chart_test.dart",
  "test/features/practice/session/setup_validation_test.dart",
  "test/features/practice/session/session_transitions_test.dart",
  "test/features/practice/session/pause_recovery_test.dart",
  "test/features/practice/session/result_navigation_test.dart",
  "test/fixtures/practice/session/",
  "test/ui/goldens/",
  "test/ui/ui_inventory_test.dart",
  "test/app/navigation/adaptive_scaffold_test.dart",
  "test/app/navigation/tab_state_restoration_test.dart",
  "test/core/screen_size_guard_test.dart",
  "docs/rounds/e13-r21-practice-session-ui.md",
]
gate_tests = [
  "test/features/practice/session/setup_validation_test.dart",
  "test/features/practice/session/session_transitions_test.dart",
  "test/features/practice/session/pause_recovery_test.dart",
  "test/features/practice/session/result_navigation_test.dart",
  "test/ui/goldens/e13_r21_screens_golden_test.dart",
  "test/ui/ui_inventory_test.dart",
  "test/app/navigation/adaptive_scaffold_test.dart",
  "test/app/navigation/tab_state_restoration_test.dart",
  "test/core/screen_size_guard_test.dart",
  "test/core/architecture_dependency_test.dart",
  "test/features/practice/domain/domain_purity_test.dart",
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

**Kockázat = high, indoklás:** a gyakorló-session birtokolja a mikrofon-erőforrást (authorization), és teljesítmény-adatot ír a naplóba.

### R1 — `lib/l10n/app_{en,hu}.arb` GENERÁLT aggregátum → a FORRÁS a szegmens

A kör fája ma **236** l10n-kulcsot használ, és mind feloldható: `app` = 236 kulcs.

A kör ezért **nem tudott volna egyetlen szöveget sem írni** a saját listáján
belül. Feloldás — H3 lista-tágítás, **user-engedéllyel (2026-08-25)**, a
lehető legszűkebb alakban:

- `practice` → nincs saját fragmentuma, a kulcsai a `base/app_*.arb` szegmensben élnek

Az aggregátum a listán MARAD, de **kizárólag generált kimenetként**
(`dart run tool/gen_l10n_segments.dart --write`); a merge-elt precedens
egységesen a forrást ÉS a regenerált aggregátumot is commitolja (E09-R26
`df0ad3dd`, E13-R12 `376b8a1d`, E13-R10 `b11ab2ed`). **Új fragmentum NEM
készül**, ezért a `test/l10n/arb_parity_test.dart` beégetett szegmens-listáját
sem kell bővíteni — a felvett források mind szerepelnek benne.

### R2 — a kör SAJÁT feature-fáján élő, ma zöld widget-tesztek (FELVÉVE)

Ezek közvetlenül a migrálandó képernyőkre állítanak, tehát a migráció után
pirosra váltanának, ami a §0 szerint `blocked` lenne:

  - `test/features/practice/presentation/chord_change_view_test.dart`
  - `test/features/practice/presentation/chord_progression_view_test.dart`
  - `test/features/practice/presentation/free_practice_view_test.dart`
  - `test/features/practice/presentation/practice_a11y_audit_test.dart`
  - `test/features/practice/presentation/practice_highway_scaling_test.dart`
  - `test/features/practice/presentation/practice_highway_test.dart`
  - `test/features/practice/presentation/practice_hub_screen_test.dart`
  - `test/features/practice/presentation/practice_result_screen_test.dart`
  - `test/features/practice/presentation/practice_routing_test.dart`
  - `test/features/practice/presentation/practice_session_lifecycle_test.dart`
  - `test/features/practice/presentation/practice_session_screen_test.dart`
  - `test/features/practice/presentation/practice_setup_screen_test.dart`
  - `test/features/practice/presentation/practice_vision_dimension_test.dart`
  - `test/features/practice/presentation/rhythm_only_view_test.dart`
  - `test/features/practice/presentation/speed_builder_progress_test.dart`
  - `test/features/practice/presentation/strum_pattern_view_test.dart`
  - `test/features/practice/presentation/timing_bias_chart_test.dart`

**A jogosultság szűk:** a teszteket az ÚJ widgetekre kell ráállítani. A lefedett
viselkedést gyengíteni, cellát törölni vagy `skip`-elni **TILOS** — az a mérce
meggyengítése, amit a gate-guard emberhez eszkalál.

### R3 — keresztmetszeti tesztek (NEM kerültek listára — figyelmeztetés)

A kör fájára hivatkozó további widget-tesztek közös infrastruktúrán élnek
(`test/app/**`, `test/core/**`, más feature-ek fái) — 7 ilyen fájl van. Ezeket a kör
**NEM** szerkesztheti: ha egy elbukik, az `blocked` jelzés és célzott
brief-revízió, nem csendes átírás. A körbe húzásuk a scope-fegyelem feladása
lenne.

### R4 — a képernyő-leltár őre (H3 önjavító kör, ADR 0112, 2026-08-25)

A `test/ui/ui_inventory_test.dart` **repó-szintű** őr: a `tool/ui_inventory.dart`
a `lib/features/**` fa `_screen.dart` végű fájljait számolja, a teszt pedig
EGZAKT `hasLength(...)`-et állít rájuk. Ez a kör a(z) `lib/features/practice/` könyvtár-előtag
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

### S11 — az örökség-képernyőt PINNELŐ, listán kívüli tesztek (2026-08-25)

A kör lecserél legalább egy MEGLÉVŐ képernyőt, amelynek a TÍPUSÁT a brief
listáján kívül élő teszt pinneli. Mérve a `tools/brief-lint.py` `S11`
szabályával (import ÉS típusnév együtt), a `main @ b28bb1bf` fán:

- `test/app/navigation/adaptive_scaffold_test.dart`
- `test/app/navigation/tab_state_restoration_test.dart`
- `test/core/screen_size_guard_test.dart`

Ez pontosan az a halt-osztály, amelyik az **E13-R16/F9**-et (full-gate
32867296946, `hasLength(79)` vs 81) és az **E13-R17/H3**-at (`flutter test
test/app/navigation/` +33 → +30 -3) megállította: az őr a listán kívül él, a
felvétele az orchestrátornak TÁGÍTÁS ([L478](../LESSONS.md)), tehát a kör H3-ban
áll meg, mielőtt egyetlen sor kód megszületne. A fenti fájlok ezért mostantól
az `allowed_paths`-on ÉS a `gate_tests`-en is szerepelnek.

**A jogosultság PONTOSAN a lecserélt képernyő típusának átírása.** Cella
törlése, `skip`-je, küszöb-lazítása vagy az állítás gyengítése TILOS — az a
mérce meghamisítása. Ha a kör bizonyíthatóan nem cseréli le a képernyőt, a kör
pre-flightja mondja ki ezt a mérést, és hagyja a cellákat érintetlenül.

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
- `test/features/practice/domain/domain_purity_test.dart`
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

Az UI-18–UI-20 (gyakorlás-beállítás, aktív session, szünet és helyreállítás)
implementálása az új Stage-, űrlap- és helyreállítás-komponensekkel
(SDD Ch13 Kör 21).

## 2. Jelenlegi állapot — mért tények

- Az R09 StageScaffoldja és transportja, az R11 űrlapelemei és az R13
  megerősítés-rendszere készen állnak.
- A gyakorlási állapotgép **létező** réteg — a UI hozzá kapcsolódik.
- Az ADR 0276 kimondta: a Stage layout nem birtokol erőforrást; a session
  indítása felhasználói szándékra történik.

## 3. Scope

**Benne van:** a beállítási felület (paraméterek, készenlét, engedély) · az
aktív session Stage-elrendezése gyakorlat-specifikus slotokkal · a szünet és
helyreállítás overlay felhasználói és rendszer-megszakítás állapotokkal · a UI
kapcsolása a meglévő állapotgéphez · rossz hangolás, degradált képesség,
gyenge jel és háttérből visszatérés állapotai · **fake órán és motoron**
alapuló determinisztikus tesztek.

**NINCS benne (tilos):** üzleti állapot tárolása widgetben · a gyakorlási
állapotgép vagy a pontozás módosítása · DSP (AGENTS.md §9) · más képernyők ·
`docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/practice/` | a három felület migrációja |
| `lib/l10n/base/app_{en,hu}.arb` | **FORRÁS** — a session-szövegek (a kör feature-ei még nem migráltak, a kulcsaik itt élnek) |
| `lib/l10n/app_{en,hu}.arb` | **CSAK GENERÁLT KIMENET** — kizárólag `dart run tool/gen_l10n_segments.dart --write`, kézzel írni TILOS |
| `test/features/…` (17 meglévő teszt) | ma zöld, a migrált képernyőkre állítandó — lásd §0.0 R2 |
| `test/features/practice/session/*_test.dart` (4) | a §6 cellái |
| `test/ui/ui_inventory_test.dart` | **repó-szintű képernyő-leltár őr** — a kör új `lib/features/**/*_screen.dart`-ot hozhat, ezért az egzakt `hasLength(...)` elmozdul; a jogosultság PONTOSAN a szám emelése, más állítás nem érinthető (§0.0/R4) |
| `docs/rounds/e13-r21-…md` | a §10 handoff |

**Tilos zóna:** `lib/features/**` a `practice/` KIVÉTELÉVEL ·
`lib/core/design_system/**` · `lib/core/theme/**` · `docs/adr/**` ·
`docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések

### 5.1 A widget NEM tárol üzleti állapotot

A session állapota az állapotgépé. A widget megjelenít és eseményt küld —
különben két igazságforrás keletkezik, és a háttérből visszatérés után
elcsúsznak.

**NEM elfogadható gyengítés:** „csak a számláló marad a widgetben, az úgyis
egyszerű". A háttérből visszatérés pont ezt nullázza.

### 5.2 A Pause/Resume NEM duplikál eseményt

Ismételt koppintás, rendszer-megszakítás és visszatérés kombinációjából sem
keletkezhet két esemény — az meghamisítaná a gyakorlási statisztikát.

### 5.3 Az eredményre navigálás PONTOSAN EGYSZER történik

Az ADR 0279 §5 mintája: a session lezárása egyetlen navigációt vált ki, akkor
is, ha a lezárás több forrásból érkezik.

### 5.4 A session indítása REPRODUKÁLHATÓ a konfigurációból

Ugyanaz a beállítás ugyanazt a sessiont adja — enélkül a hibák nem
reprodukálhatók, és az eredmények nem összevethetők.

### 5.5 A kilépés adatvesztési következménye VILÁGOS

Az ADR 0279 §1 szerint: a megerősítés kimondja, mi vész el — nem „Igen/Nem".

### 5.6 A UI NEM blokkolja a DSP-t

Nehéz elrendezési munka nem futhat az audio-feldolgozás rovására; a felület
frissítése nem tarthatja fel a feldolgozást.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A session ugyanabból a konfigurációból reprodukálható | `setup_validation_test.dart` |
| A2 | A Pause/Resume nem duplikál eseményt | `session_transitions_test.dart` |
| A3 | Az eredményre navigálás pontosan egyszer történik | `result_navigation_test.dart` |
| A4 | A widget nem tárol üzleti állapotot (háttérből visszatérve helyes) | `pause_recovery_test.dart` |
| A5 | A kilépés adatvesztési következménye szövegben megjelenik | `session_transitions_test.dart` |
| A6 | Rossz hangolás / degradált képesség / gyenge jel külön állapot | ugyanott |
| A7 | A beállítás validációja hibás bemenetet nem enged tovább | `setup_validation_test.dart` |
| A8 | Portrait és landscape elrendezésben nincs túlcsordulás | `session_transitions_test.dart` |
| A9 | A kör §3-ban megnevezett MINDEN képernyőről golden-felvétel készül és be van commitolva — 412×915 compact portrait ÉS `textScaleFactor: 2.0` | `e13_r21_screens_golden_test.dart` + a `test/ui/goldens/*.png` a diffben |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A számláló a widget állapotában | **A4** |
| A Resume új „session indult" eseményt küld | **A2** |
| A lezárás két forrásból kétszer navigál | **A3** |
| A konfiguráció egy mezője nem kerül át | A1 |
| „Biztos vagy benne? Igen/Nem" kilépéskor | **A5** |
| A gyenge jel és a rossz hangolás összevonva | A6 |
| A képernyő elcsúszik, túlcsordul vagy nagy szövegméretnél olvashatatlan | **A9** |

**Az eredmény-navigáció három kötelező cellája** (a küszöb: hányszor futhat):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | a session megszakad mentés nélkül | **0** navigáció az eredményre |
| rajta (a küszöbön) | egyszeri lezárás | **pontosan 1** navigáció |
| a küszöb fölött | lezárás + a rendszer is lezárja (kettős forrás) | **pontosan 1** navigáció |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** tedd a session
számlálóját a widget állapotába → az **A4** cellának PIROSNAK kell lennie →
állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/practice/session/setup_validation_test.dart test/features/practice/session/session_transitions_test.dart test/features/practice/session/pause_recovery_test.dart test/features/practice/session/result_navigation_test.dart test/ui/goldens/e13_r21_screens_golden_test.dart test/ui/ui_inventory_test.dart test/app/navigation/adaptive_scaffold_test.dart test/app/navigation/tab_state_restoration_test.dart test/core/screen_size_guard_test.dart test/core/architecture_dependency_test.dart test/features/practice/domain/domain_purity_test.dart test/tooling/dio_factory_guard_test.dart test/tooling/preferences_plugin_import_guard_test.dart test/tooling/route_literal_guard_test.dart
```

**A golden-felvétel (A9) rögzítése — a mérce ÚJ, nem alku tárgya:** a képernyő
minden állapotát NEM kell felvenni, a §3 szerinti alap-nézet elég, de a két
keret (412×915 compact portrait és ugyanaz `textScaleFactor: 2.0` mellett)
KÖTELEZŐ. Minta és futó precedens: `test/features/live/chord_timeline_golden_test.dart`
(valódi kapu, nem `skip`-elt rögzítő). Előállítás:

```bash
~/flutter/bin/flutter test --update-goldens test/ui/goldens/e13_r21_screens_golden_test.dart
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

## 8. Implementációs sorrend

1. A beállítási felület + validáció + reprodukálhatósági cella.
2. Az aktív session Stage-elrendezése, az állapotgéphez kapcsolva.
3. A szünet/helyreállítás overlay, felhasználói és rendszer-megszakítással.
4. A Pause/Resume esemény-duplikáció cellája.
5. Az eredmény-navigáció három cellája.
6. A kilépési megerősítés következmény-központú szövege.
7. A valódi-sértés próba, §10-be dokumentálva.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A widgetbe szivárgó állapot.** „Csak egy számláló" — és a háttérből
  visszatérés után hamis eredményt ad (A4).
- **A kettős lezárás.** Ritka, de duplikált eredményt vagy dupla navigációt
  okoz (A3).
- **Az elnagyolt kilépési szöveg.** A gyakorlás közbeni véletlen kilépés a
  leggyakoribb adatvesztési út (A5).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
